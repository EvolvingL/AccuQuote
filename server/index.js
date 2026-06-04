/**
 * AccuQuote — Express API server
 * Runs on Render (or any Node host).
 *
 * Required environment variables:
 *   ANTHROPIC_API_KEY          — Anthropic API key (never sent to device)
 *   STRIPE_SECRET_KEY          — Stripe secret key
 *   STRIPE_WEBHOOK_SECRET      — Stripe webhook signing secret
 *   FIREBASE_SERVICE_ACCOUNT   — JSON string of Firebase service account credentials
 *                                 (also grants FCM access — no extra credential needed)
 *   BEEHIIV_API_KEY            — Beehiiv newsletter key
 *   BEEHIIV_PUBLICATION_ID     — Beehiiv publication ID
 *   ADMIN_SECRET               — Long random string protecting /admin/* endpoints
 *
 * Endpoints:
 *   POST /api/claude                        — proxies Claude requests (auth required)
 *   POST /api/quote/discover                — section discovery via Haiku (auth + entitlement)
 *   POST /api/quote/section                 — per-section Sonnet streaming (auth + entitlement)
 *   GET  /api/entitlement                   — returns user's current tier (auth required)
 *   POST /api/stripe/payment-link           — deposit payment link for customers
 *   POST /api/stripe/create-checkout        — subscription checkout session
 *   POST /api/stripe/webhook                — Stripe webhook (entitlement fulfilment)
 *   GET  /api/health                        — health check
 *   POST /api/push/register                 — device registers APNs token (auth required)
 *   POST /api/admin/broadcast               — push to segment + A/B test (admin)
 *   POST /api/push/personal                 — personalised push to single user (admin)
 *   GET  /api/admin/push/log                — last 50 push events (admin)
 *   GET  /*                                 — serves the web app static files
 */

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { createServer } from 'http';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3000;

// ── Firebase Admin ────────────────────────────────────────────────────────────
// Initialised lazily so the server still boots without credentials (for local dev
// without Firebase). All protected endpoints check initFirebase() before use.

let adminApp = null;
let adminAuth = null;
let adminFirestore = null;

function initFirebase() {
  if (adminApp) return true;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountJson) {
    console.warn('[Firebase] FIREBASE_SERVICE_ACCOUNT not set — auth middleware disabled');
    return false;
  }
  try {
    // Dynamic import because firebase-admin is ESM-unfriendly; use createRequire
    const { createRequire } = await import('module');
    const require = createRequire(import.meta.url);
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      adminApp = admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(serviceAccountJson)),
      });
    } else {
      adminApp = admin.apps[0];
    }
    adminAuth = admin.auth();
    adminFirestore = admin.firestore();
    return true;
  } catch (e) {
    console.error('[Firebase] Init failed:', e.message);
    return false;
  }
}

// ── Auth middleware ───────────────────────────────────────────────────────────
// Verifies Firebase ID token in Authorization: Bearer <token> header.
// Attaches decoded token to req.user.

async function requireAuth(req, res, next) {
  if (!initFirebase()) {
    // Firebase not configured — allow through in local dev only
    if (process.env.NODE_ENV === 'production') {
      return res.status(503).json({ error: 'Auth service unavailable' });
    }
    req.user = { uid: 'dev-user' };
    return next();
  }

  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing auth token' });
  }
  const token = header.slice(7);
  try {
    const decoded = await adminAuth.verifyIdToken(token);
    req.user = decoded;
    next();
  } catch (e) {
    return res.status(401).json({ error: 'Invalid or expired auth token' });
  }
}

// ── Entitlement helper ────────────────────────────────────────────────────────
// Returns the user's current tier: 'free' | 'solo' | 'team' | 'crew'
// Ground truth is Firestore; this is called server-side before every
// quote generation call so client-side bypass = silent server rejection.

async function getUserTier(uid) {
  if (!adminFirestore) return 'free';
  try {
    const doc = await adminFirestore.doc(`users/${uid}/entitlement/subscription`).get();
    if (!doc.exists) return 'free';
    const data = doc.data();
    if (data.status !== 'active') return 'free';
    return data.tier || 'free';  // 'solo' | 'team' | 'crew'
  } catch {
    return 'free';
  }
}

// Middleware: requires an active paid tier to proceed
async function requirePaidTier(req, res, next) {
  const tier = await getUserTier(req.user.uid);
  if (tier === 'free') {
    return res.status(403).json({ error: 'subscription_required', tier });
  }
  req.userTier = tier;
  next();
}

// ── Raw body for Stripe webhooks ──────────────────────────────────────────────
app.use('/api/stripe/webhook', express.raw({ type: 'application/json' }));

// ── JSON body parser for everything else ─────────────────────────────────────
app.use(express.json());

// ── Security headers ──────────────────────────────────────────────────────────
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(self), geolocation=(self)');
  next();
});

// ── CORS ──────────────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  const origin = req.headers.origin || '';
  const allowed =
    origin === 'http://localhost:3000' ||
    origin === 'http://localhost:5000' ||
    origin.endsWith('.onrender.com') ||
    origin.endsWith('.accuquote.co.uk');

  if (allowed || !origin) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') { res.sendStatus(200); return; }
  next();
});

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Entitlement check ─────────────────────────────────────────────────────────
// iOS app polls this on launch to hydrate EntitlementManager.
app.get('/api/entitlement', requireAuth, async (req, res) => {
  const tier = await getUserTier(req.user.uid);
  res.json({ uid: req.user.uid, tier });
});

// ── Quote section discovery (Phase 1 — Haiku, fast) ──────────────────────────
// Auth + paid tier required. iOS QuoteGenerationService calls this instead of
// hitting Anthropic directly.
app.post('/api/quote/discover', requireAuth, requirePaidTier, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'API key not configured' });

  const { jobDescription, claudeContext } = req.body || {};
  if (!jobDescription) return res.status(400).json({ error: 'Missing jobDescription' });

  const prompt = `${claudeContext ? claudeContext + '\n\n' : ''}JOB: ${jobDescription}

List the distinct trade sections that need quoting for this job.
Include only sections within this tradesperson's scope and trade.
Return ONLY a JSON array, no markdown, no prose.
Each element: {"sectionKey":"snake_case_id","sectionLabel":"Human Label","tradeScope":"brief scope of what this section covers"}
Maximum 10 sections. Do not include project management or preliminaries.`;

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 800,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      return res.status(response.status).json({ error: `Anthropic error: ${err}` });
    }

    const data = await response.json();
    const text = data.content?.[0]?.text || '';
    res.json({ text });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Per-section quote generation (Phase 2 — Sonnet, streaming) ───────────────
// Auth + paid tier required. Streams SSE back to the iOS app.
app.post('/api/quote/section', requireAuth, requirePaidTier, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'API key not configured' });

  const {
    sectionLabel, tradeScope, jobDescription, claudeContext,
    roomDimensions, preferredSupplier, usualItems,
  } = req.body || {};

  if (!sectionLabel || !jobDescription) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const rd = roomDimensions || {};
  const prompt = `${claudeContext ? claudeContext + '\n\n' : ''}OVERALL JOB: ${jobDescription}
SECTION TO PRICE: ${sectionLabel}
SCOPE: ${tradeScope || ''}

ROOM: ${rd.roomType || ''}
DIMENSIONS: ${rd.lengthStr || '?'}m × ${rd.widthStr || '?'}m × ${rd.heightStr || '?'}m
FLOOR AREA: ${rd.floorArea ? rd.floorArea.toFixed(1) : '?'}m²
WALL AREA: ${rd.wallArea ? rd.wallArea.toFixed(1) : '?'}m²
DOORS: ${rd.doorCount ?? 0}  WINDOWS: ${rd.windowCount ?? 0}

PREFERRED SUPPLIER: ${preferredSupplier || 'any'}
${usualItems ? 'PRODUCTS THEY REGULARLY ORDER: ' + usualItems : ''}

Price ONLY the '${sectionLabel}' scope. Be exhaustive — include every line item.
Match all materials to REAL products at ${preferredSupplier || 'the preferred supplier'}. Include exact SKU codes.

OUTPUT: Return ONLY a single raw JSON object — no markdown, no prose.
Schema: {"labourDays":2.0,"labourRate":280.0,"items":[{"description":"...","qty":1.0,"unit":"each","unitPrice":12.50,"sku":"123456","supplier":"..."}],"vatRate":20,"notes":"..."}
No item cap — include everything needed. Keep descriptions concise (under 70 chars).`;

  // Stream SSE back to the app
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'accept': 'text/event-stream',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 4096,
        stream: true,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!upstream.ok) {
      const err = await upstream.text();
      res.write(`data: ${JSON.stringify({ error: err })}\n\n`);
      return res.end();
    }

    // Pipe the SSE stream through
    for await (const chunk of upstream.body) {
      res.write(chunk);
    }
    res.end();
  } catch (err) {
    res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
    res.end();
  }
});

// ── AI Profile update proxy (existing /api/claude — now auth-protected) ───────
app.post('/api/claude', requireAuth, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'ANTHROPIC_API_KEY not set on server' });

  const { system, userPrompt, maxTokens = 2000 } = req.body || {};
  if (!userPrompt) return res.status(400).json({ error: 'Missing userPrompt' });

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: maxTokens,
        ...(system ? { system } : {}),
        messages: [{ role: 'user', content: userPrompt }],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      return res.status(response.status).json({ error: `Anthropic error: ${err}` });
    }

    const data = await response.json();
    const content = data.content?.[0]?.text || '';
    res.json({ content });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Stripe: subscription checkout session ─────────────────────────────────────
// Creates a Stripe Checkout session for a subscription tier.
// firebaseUid is stored as client_reference_id so the webhook can link the payment.
app.post('/api/stripe/create-checkout', requireAuth, async (req, res) => {
  const stripeKey = process.env.STRIPE_SECRET_KEY;
  if (!stripeKey) return res.status(500).json({ error: 'STRIPE_SECRET_KEY not set' });

  const { tier, interval } = req.body || {};  // tier: 'solo'|'team'|'crew', interval: 'month'|'year'
  const uid = req.user.uid;
  const email = req.user.email || '';

  // Price IDs — set these in Stripe Dashboard and add as env vars
  const priceMap = {
    solo_month:  process.env.STRIPE_PRICE_SOLO_MONTHLY,
    solo_year:   process.env.STRIPE_PRICE_SOLO_ANNUAL,
    team_month:  process.env.STRIPE_PRICE_TEAM_MONTHLY,
    team_year:   process.env.STRIPE_PRICE_TEAM_ANNUAL,
    crew_month:  process.env.STRIPE_PRICE_CREW_MONTHLY,
    crew_year:   process.env.STRIPE_PRICE_CREW_ANNUAL,
  };

  const priceId = priceMap[`${tier}_${interval}`];
  if (!priceId) return res.status(400).json({ error: `Unknown tier/interval: ${tier}/${interval}` });

  try {
    const params = new URLSearchParams({
      'mode': 'subscription',
      'line_items[0][price]': priceId,
      'line_items[0][quantity]': '1',
      'client_reference_id': uid,
      'customer_email': email,
      'metadata[firebaseUid]': uid,
      'metadata[tier]': tier,
      // Return URL scheme — iOS app handles accuquote://stripe-return
      'success_url': 'accuquote://stripe-return?status=success&tier=' + tier,
      'cancel_url':  'accuquote://stripe-return?status=cancel',
      'subscription_data[metadata][firebaseUid]': uid,
      'subscription_data[metadata][tier]': tier,
    });

    const response = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${stripeKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params,
    });

    const data = await response.json();
    if (!response.ok) return res.status(500).json({ error: data.error?.message || 'Stripe error' });

    res.json({ url: data.url, sessionId: data.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Stripe: webhook (entitlement fulfilment) ──────────────────────────────────
// Stripe sends events here. We write entitlement to Firestore.
// Register this URL in Stripe Dashboard: https://your-render-domain/api/stripe/webhook
app.post('/api/stripe/webhook', async (req, res) => {
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  const stripeKey = process.env.STRIPE_SECRET_KEY;

  if (!webhookSecret || !stripeKey) {
    console.error('[Webhook] STRIPE_WEBHOOK_SECRET or STRIPE_SECRET_KEY not set');
    return res.status(500).json({ error: 'Webhook not configured' });
  }

  // Verify Stripe signature
  const sig = req.headers['stripe-signature'];
  let event;
  try {
    // Manual HMAC verification (no stripe npm package needed)
    const crypto = await import('crypto');
    const payload = req.body; // raw Buffer
    const [, timestampPart, v1Part] = sig.split(',').reduce((acc, part) => {
      const [k, v] = part.split('=');
      acc[k === 't' ? 0 : k === 'v1' ? 1 : 2] = v;
      // eslint-disable-next-line no-unused-vars
      return acc;
    }, []);

    const parts = sig.split(',');
    const t = parts.find(p => p.startsWith('t='))?.slice(2);
    const v1 = parts.find(p => p.startsWith('v1='))?.slice(3);
    const signedPayload = `${t}.${payload.toString('utf8')}`;
    const expected = crypto.default
      .createHmac('sha256', webhookSecret)
      .update(signedPayload)
      .digest('hex');

    if (expected !== v1) {
      return res.status(400).json({ error: 'Invalid signature' });
    }

    event = JSON.parse(payload.toString('utf8'));
  } catch (err) {
    return res.status(400).json({ error: `Webhook parse error: ${err.message}` });
  }

  if (!adminFirestore) {
    console.warn('[Webhook] Firestore not available, skipping entitlement update');
    return res.json({ received: true });
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;
        const uid = session.metadata?.firebaseUid || session.client_reference_id;
        const tier = session.metadata?.tier || 'solo';
        if (uid) {
          await adminFirestore
            .doc(`users/${uid}/entitlement/subscription`)
            .set({ tier, status: 'active', updatedAt: Date.now(), stripeSessionId: session.id }, { merge: true });
          console.log(`[Webhook] Activated ${tier} for ${uid}`);
        }
        break;
      }
      case 'customer.subscription.updated': {
        const sub = event.data.object;
        const uid = sub.metadata?.firebaseUid;
        const tier = sub.metadata?.tier || 'solo';
        const status = sub.status === 'active' ? 'active' : 'inactive';
        if (uid) {
          await adminFirestore
            .doc(`users/${uid}/entitlement/subscription`)
            .set({ tier, status, updatedAt: Date.now(), stripeSubscriptionId: sub.id }, { merge: true });
        }
        break;
      }
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        const uid = sub.metadata?.firebaseUid;
        if (uid) {
          await adminFirestore
            .doc(`users/${uid}/entitlement/subscription`)
            .set({ tier: 'free', status: 'inactive', updatedAt: Date.now() }, { merge: true });
          console.log(`[Webhook] Deactivated subscription for ${uid}`);
        }
        break;
      }
      default:
        break;
    }
  } catch (err) {
    console.error('[Webhook] Firestore update error:', err.message);
  }

  res.json({ received: true });
});

// ── Stripe: deposit payment link (existing, now auth-protected) ───────────────
app.post('/api/stripe/payment-link', requireAuth, requirePaidTier, async (req, res) => {
  const stripeKey = process.env.STRIPE_SECRET_KEY;
  if (!stripeKey) return res.status(500).json({ error: 'STRIPE_SECRET_KEY not set on server' });

  const { depositAmount, customerName, jobDescription, traderName } = req.body || {};
  if (!depositAmount || isNaN(depositAmount) || depositAmount <= 0) {
    return res.status(400).json({ error: 'Invalid depositAmount' });
  }

  const depositPence = Math.round(depositAmount * 100);
  const servicePence = Math.round(depositAmount * 0.01 * 100);

  const description = [
    jobDescription ? `Job: ${jobDescription}` : null,
    'Deposit request via AccuQuote',
    traderName ? `Trader: ${traderName}` : null,
  ].filter(Boolean).join(' · ');

  try {
    const priceRes = await fetch('https://api.stripe.com/v1/prices', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${stripeKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        'currency': 'gbp',
        'unit_amount': String(depositPence),
        'product_data[name]': customerName ? `Deposit — ${customerName}` : 'Deposit',
        'product_data[metadata][job]': (jobDescription || '').substring(0, 500),
        'product_data[metadata][trader]': traderName || '',
      }),
    });

    if (!priceRes.ok) {
      const err = await priceRes.json();
      return res.status(500).json({ error: err.error?.message || 'Stripe price error' });
    }
    const price = await priceRes.json();

    const linkRes = await fetch('https://api.stripe.com/v1/payment_links', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${stripeKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        'line_items[0][price]': price.id,
        'line_items[0][quantity]': '1',
        'metadata[source]': 'accuquote',
        'metadata[customer]': customerName || '',
        'metadata[job]': (jobDescription || '').substring(0, 500),
        'metadata[accuquote_fee_pence]': String(servicePence),
      }),
    });

    const linkBody = await linkRes.json();
    if (!linkRes.ok) return res.status(500).json({ error: linkBody.error?.message || 'Stripe link error' });
    if (!linkBody.url) return res.status(500).json({ error: 'Stripe did not return a payment URL' });

    res.json({ url: linkBody.url, depositAmount, serviceFee: servicePence / 100 });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Beehiiv subscribe proxy ───────────────────────────────────────────────────
app.post('/api/subscribe', async (req, res) => {
  const apiKey = process.env.BEEHIIV_API_KEY;
  const pubId  = process.env.BEEHIIV_PUBLICATION_ID;
  if (!apiKey || !pubId) return res.status(500).json({ error: 'Beehiiv credentials not configured' });

  const { email, trade } = req.body || {};
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: 'Invalid email' });
  }

  try {
    const response = await fetch(`https://api.beehiiv.com/v2/publications/${pubId}/subscriptions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` },
      body: JSON.stringify({
        email, utm_source: 'prelaunch', utm_medium: 'organic',
        custom_fields: trade ? [{ name: 'trade', value: trade }] : [],
        send_welcome_email: true, reactivate_existing: false,
      }),
    });

    const data = await response.json();
    if (response.status === 201 || response.status === 200) return res.json({ ok: true });
    if (response.status === 409 || data?.errors?.find?.(e => e.includes('already'))) {
      return res.status(409).json({ error: 'already_subscribed' });
    }
    return res.status(response.status).json({ error: data?.message || 'Beehiiv error' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Admin dashboard ───────────────────────────────────────────────────────────
// Protected by ADMIN_SECRET env var (Bearer token in Authorization header).
// Provides: user list, CSV export, broadcast push notification.
//
// ADMIN_SECRET — a long random string set in Render environment variables.
// Usage: Authorization: Bearer <ADMIN_SECRET>

function requireAdmin(req, res, next) {
  const secret = process.env.ADMIN_SECRET;
  if (!secret) {
    if (process.env.NODE_ENV === 'production') {
      return res.status(503).json({ error: 'Admin not configured' });
    }
    return next(); // dev: allow through
  }
  const header = req.headers.authorization || '';
  if (header !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'Unauthorised' });
  }
  next();
}

// GET /admin — serve the admin HTML dashboard
app.get('/admin', requireAdmin, (req, res) => {
  res.sendFile(join(__dirname, 'admin.html'));
});

// GET /api/admin/users — list all users with entitlement + scan count
// Queries Firestore users collection (top-level documents).
app.get('/api/admin/users', requireAdmin, async (req, res) => {
  if (!adminFirestore) {
    return res.status(503).json({ error: 'Firestore not available' });
  }

  try {
    // Firestore doesn't support arbitrary cross-user queries without a flat collection.
    // We read the top-level `users` collection and sub-doc entitlement.
    const usersSnap = await adminFirestore.collection('users').limit(500).get();
    const rows = [];

    await Promise.all(usersSnap.docs.map(async (userDoc) => {
      const uid = userDoc.id;
      const userData = userDoc.data() || {};

      // Entitlement
      let tier = 'free';
      let subStatus = 'none';
      try {
        const entDoc = await adminFirestore.doc(`users/${uid}/entitlement/subscription`).get();
        if (entDoc.exists) {
          const ent = entDoc.data();
          tier = ent.tier || 'free';
          subStatus = ent.status || 'none';
        }
      } catch {}

      rows.push({
        uid,
        email: userData.email || '',
        trade: userData.trade || '',
        tier,
        subStatus,
        totalScans: userData.totalScans || 0,
        lastActive: userData.lastActive ? new Date(userData.lastActive).toISOString() : '',
        engagementTier: userData.engagementTier || 'user',
        createdAt: userData.createdAt ? new Date(userData.createdAt).toISOString() : '',
      });
    }));

    rows.sort((a, b) => (b.totalScans || 0) - (a.totalScans || 0));
    res.json({ users: rows, total: rows.length });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/users.csv — same data as CSV export
app.get('/api/admin/users.csv', requireAdmin, async (req, res) => {
  if (!adminFirestore) {
    return res.status(503).json({ error: 'Firestore not available' });
  }

  try {
    const usersSnap = await adminFirestore.collection('users').limit(500).get();
    const rows = [];

    await Promise.all(usersSnap.docs.map(async (userDoc) => {
      const uid = userDoc.id;
      const userData = userDoc.data() || {};
      let tier = 'free';
      let subStatus = 'none';
      try {
        const entDoc = await adminFirestore.doc(`users/${uid}/entitlement/subscription`).get();
        if (entDoc.exists) {
          const ent = entDoc.data();
          tier = ent.tier || 'free';
          subStatus = ent.status || 'none';
        }
      } catch {}

      rows.push([
        uid,
        userData.email || '',
        userData.trade || '',
        tier,
        subStatus,
        userData.totalScans || 0,
        userData.engagementTier || 'user',
        userData.lastActive ? new Date(userData.lastActive).toISOString() : '',
        userData.createdAt ? new Date(userData.createdAt).toISOString() : '',
      ]);
    }));

    rows.sort((a, b) => (b[5] || 0) - (a[5] || 0));

    const header = 'uid,email,trade,tier,subStatus,totalScans,engagementTier,lastActive,createdAt\n';
    const csv = header + rows.map(r =>
      r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')
    ).join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="accuscan-users-${Date.now()}.csv"`);
    res.send(csv);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/admin/broadcast — write a broadcast doc to Firestore
// ══════════════════════════════════════════════════════════════════════════════
// PUSH NOTIFICATION SYSTEM
// ══════════════════════════════════════════════════════════════════════════════
//
// Architecture:
//   • Devices register their APNs token at POST /api/push/register (auth required)
//   • Tokens + user metadata stored in Firestore `devices/{uid}` collection
//   • Server sends via Firebase Admin messaging() — no FCM SDK on iOS needed
//   • Three delivery modes:
//       1. Broadcast  — POST /api/admin/broadcast  (admin, segments + A/B variants)
//       2. Personal   — POST /api/push/personal    (admin, single uid, server-data templated)
//       3. Programmatic — sendPush() helper used internally (e.g. after Stripe webhook)
//
// Environment variable required:
//   FIREBASE_SERVICE_ACCOUNT  — already set (used by Firebase Admin auth/firestore)
//   The same service account credentials provide FCM access automatically.
//
// Firestore schema:
//   devices/{uid}  {
//     token:       string   — APNs device token (hex string)
//     uid:         string
//     trade:       string   — e.g. "electrician"
//     tier:        string   — 'free'|'solo'|'team'|'crew'
//     quoteCount:  number   — total quotes sent (for personalisation)
//     platform:    string   — 'ios'
//     appVersion:  string
//     updatedAt:   number   — ms timestamp
//   }
//   push_log/{auto}  {
//     type:        'broadcast'|'personal'
//     broadcastId: string (broadcast only)
//     uid:         string (personal only)
//     title:       string
//     body:        string
//     variant:     'a'|'b'|null
//     sentAt:      number
//     successCount: number
//     failureCount: number
//   }

// ── FCM send helper ───────────────────────────────────────────────────────────
// Sends a push notification to a single APNs token via Firebase Admin messaging().
// Returns { success: true } or { success: false, error: string }.

async function sendPush(token, title, body, data = {}) {
  if (!adminApp) return { success: false, error: 'Firebase not initialised' };
  try {
    const { createRequire } = await import('module');
    const require = createRequire(import.meta.url);
    const admin = require('firebase-admin');
    const messaging = admin.messaging();
    await messaging.send({
      token,
      notification: { title, body },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
            badge: 1,
          },
          ...data,
        },
        headers: { 'apns-priority': '10' },
      },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
    });
    return { success: true };
  } catch (err) {
    // FCM error codes that mean the token is stale — remove it
    const stale = ['messaging/registration-token-not-registered',
                   'messaging/invalid-registration-token'];
    return { success: false, error: err.code || err.message, stale: stale.includes(err.code) };
  }
}

// ── POST /api/push/register ───────────────────────────────────────────────────
// iOS app calls this on every launch (if token has rotated) or after sign-in.
// Stores the APNs token plus user metadata for targeting and personalisation.
// Body: { token, uid, trade, quoteCount, platform, appVersion }

app.post('/api/push/register', requireAuth, async (req, res) => {
  if (!adminFirestore) return res.status(503).json({ error: 'Firestore not available' });

  const { token, trade = 'general', quoteCount = 0, platform = 'ios', appVersion = '1.0' } = req.body || {};
  if (!token) return res.status(400).json({ error: 'token is required' });

  const uid  = req.user.uid;
  const tier = await getUserTier(uid);

  try {
    await adminFirestore.doc(`devices/${uid}`).set({
      token,
      uid,
      trade,
      tier,
      quoteCount,
      platform,
      appVersion,
      updatedAt: Date.now(),
    }, { merge: true });

    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/admin/broadcast ─────────────────────────────────────────────────
// Sends a push notification to a segment of users.
// Supports A/B testing: if variantA and variantB are provided, each device
// is randomly assigned to one variant and the split is recorded.
//
// Body:
//   title       string          — used for both variants unless variant overrides
//   body        string          — message body (variant A default)
//   targetTier  'all'|tier      — filter by subscription tier
//   targetTrade 'all'|trade     — filter by trade
//   variantA    { title, body } — optional A/B variant A override
//   variantB    { title, body } — optional A/B variant B override
//   deepLink    string          — optional deep link passed as notification data

app.post('/api/admin/broadcast', requireAdmin, async (req, res) => {
  if (!adminFirestore) return res.status(503).json({ error: 'Firestore not available' });

  const {
    title, body: msgBody,
    targetTier  = 'all',
    targetTrade = 'all',
    variantA, variantB,
    deepLink,
  } = req.body || {};

  if (!title || !msgBody) return res.status(400).json({ error: 'title and body are required' });

  const isAB = !!(variantA && variantB);

  // Query matching device tokens from Firestore
  let query = adminFirestore.collection('devices');
  if (targetTier  !== 'all') query = query.where('tier',  '==', targetTier);
  if (targetTrade !== 'all') query = query.where('trade', '==', targetTrade);

  let snap;
  try {
    snap = await query.limit(5000).get();
  } catch (err) {
    return res.status(500).json({ error: `Firestore query failed: ${err.message}` });
  }

  const devices = snap.docs.map(d => d.data()).filter(d => d.token);
  if (devices.length === 0) return res.json({ ok: true, sent: 0, message: 'No matching devices' });

  // Send in batches of 100 (FCM multicast limit is 500 but we use individual sends for APNs)
  let successCount = 0;
  let failureCount = 0;
  const countA = { success: 0, failure: 0 };
  const countB = { success: 0, failure: 0 };
  const staleTokenUids = [];

  const data = deepLink ? { deep_link: deepLink } : {};

  await Promise.all(devices.map(async (device) => {
    let pushTitle = title;
    let pushBody  = msgBody;
    let variant   = null;

    if (isAB) {
      // Deterministic A/B split based on uid hash — same user always gets same variant
      const hash = device.uid.charCodeAt(0) + (device.uid.charCodeAt(1) || 0);
      variant    = hash % 2 === 0 ? 'a' : 'b';
      if (variant === 'a' && variantA) {
        pushTitle = variantA.title || title;
        pushBody  = variantA.body  || msgBody;
      } else if (variant === 'b' && variantB) {
        pushTitle = variantB.title || title;
        pushBody  = variantB.body  || msgBody;
      }
    }

    const result = await sendPush(device.token, pushTitle, pushBody, data);
    if (result.success) {
      successCount++;
      if (variant === 'a') countA.success++;
      if (variant === 'b') countB.success++;
    } else {
      failureCount++;
      if (variant === 'a') countA.failure++;
      if (variant === 'b') countB.failure++;
      if (result.stale) staleTokenUids.push(device.uid);
    }
  }));

  // Remove stale tokens from the devices collection
  if (staleTokenUids.length > 0) {
    await Promise.all(staleTokenUids.map(uid =>
      adminFirestore.doc(`devices/${uid}`).delete().catch(() => {})
    ));
  }

  // Log the broadcast for analytics
  const broadcastDoc = await adminFirestore.collection('push_log').add({
    type:         'broadcast',
    title,
    body:         msgBody,
    targetTier,
    targetTrade,
    isAB,
    variantA:     variantA || null,
    variantB:     variantB || null,
    sentAt:       Date.now(),
    successCount,
    failureCount,
    abResults:    isAB ? { a: countA, b: countB } : null,
    staleRemoved: staleTokenUids.length,
  });

  res.json({
    ok:           true,
    broadcastId:  broadcastDoc.id,
    sent:         successCount,
    failed:       failureCount,
    total:        devices.length,
    ...(isAB ? { abResults: { a: countA, b: countB } } : {}),
  });
});

// ── POST /api/push/personal ───────────────────────────────────────────────────
// Sends a personalised push to a single user using server-side data.
// Supports template variables interpolated from the user's Firestore device doc.
//
// Template variables in title/body:
//   {{quoteCount}}  — total quotes sent
//   {{trade}}       — trade (e.g. "Electrician")
//   {{tier}}        — subscription tier
//
// Body: { uid, title, body, deepLink? }
// Example body: "You've sent {{quoteCount}} quotes — your best month yet 🎉"

app.post('/api/push/personal', requireAdmin, async (req, res) => {
  if (!adminFirestore) return res.status(503).json({ error: 'Firestore not available' });

  const { uid, title, body: msgBody, deepLink } = req.body || {};
  if (!uid || !title || !msgBody) {
    return res.status(400).json({ error: 'uid, title and body are required' });
  }

  // Load device data for this user
  let deviceDoc;
  try {
    deviceDoc = await adminFirestore.doc(`devices/${uid}`).get();
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }

  if (!deviceDoc.exists) return res.status(404).json({ error: 'Device not registered for this user' });

  const device = deviceDoc.data();
  if (!device.token) return res.status(404).json({ error: 'No push token for this user' });

  // Interpolate template variables
  const vars = {
    '{{quoteCount}}': String(device.quoteCount || 0),
    '{{trade}}':      capitalise(device.trade || 'tradesperson'),
    '{{tier}}':       capitalise(device.tier  || 'free'),
  };
  let pushTitle = title;
  let pushBody  = msgBody;
  for (const [key, val] of Object.entries(vars)) {
    pushTitle = pushTitle.replaceAll(key, val);
    pushBody  = pushBody.replaceAll(key, val);
  }

  const data   = deepLink ? { deep_link: deepLink } : {};
  const result = await sendPush(device.token, pushTitle, pushBody, data);

  if (!result.success) {
    if (result.stale) await adminFirestore.doc(`devices/${uid}`).delete().catch(() => {});
    return res.status(500).json({ error: result.error });
  }

  // Log
  await adminFirestore.collection('push_log').add({
    type:    'personal',
    uid,
    title:   pushTitle,
    body:    pushBody,
    sentAt:  Date.now(),
    successCount: 1,
    failureCount: 0,
  }).catch(() => {});

  res.json({ ok: true, title: pushTitle, body: pushBody });
});

// ── GET /api/admin/push/log ───────────────────────────────────────────────────
// Returns the last 50 push send events for the admin dashboard.

app.get('/api/admin/push/log', requireAdmin, async (req, res) => {
  if (!adminFirestore) return res.json({ log: [] });
  try {
    const snap = await adminFirestore
      .collection('push_log')
      .orderBy('sentAt', 'desc')
      .limit(50)
      .get();
    const log = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ log });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Capitalise helper ─────────────────────────────────────────────────────────
function capitalise(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// ── Service worker ────────────────────────────────────────────────────────────
app.get('/sw.js', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Service-Worker-Allowed', '/');
  res.sendFile(join(__dirname, '..', 'sw.js'));
});

// ── Static files ──────────────────────────────────────────────────────────────
const ROOT = join(__dirname, '..');

app.get('/', (req, res) => res.sendFile(join(ROOT, 'website.html')));
app.get('/prelaunch', (req, res) => res.sendFile(join(ROOT, 'prelaunch.html')));

const pages = ['demo', 'blog', 'how-it-works', 'referral', 'quote-cost-calculator', 'privacy-policy'];
pages.forEach(page => {
  const noCache = (req, res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.sendFile(join(ROOT, `${page}.html`));
  };
  app.get(`/${page}`, noCache);
  app.get(`/${page}.html`, noCache);
});

app.use(express.static(ROOT, {
  maxAge: '1y',
  index: false,
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.html') || filePath.endsWith('sw.js')) {
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');
      res.setHeader('Surrogate-Control', 'no-store');
    }
  },
}));

app.get('*', (req, res) => res.sendFile(join(ROOT, 'website.html')));

app.listen(PORT, () => {
  console.log(`AccuQuote server running on port ${PORT}`);
});
