/**
 * AccuQuote — Express API server
 * Runs on Render (or any Node host).
 * Set environment variable: ANTHROPIC_API_KEY
 *
 * Endpoints:
 *   POST /api/claude       — proxies Claude requests server-side
 *   GET  /api/health       — health check
 *   GET  /*                — serves the web app static files
 */

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// ── Security headers ─────────────────────────────────────────────────────────
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(self), geolocation=(self)');
  next();
});

// ── CORS ─────────────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  const origin = req.headers.origin || '';
  // Allow your Render domain, localhost for dev, and any .onrender.com subdomain
  const allowed =
    origin === 'http://localhost:3000' ||
    origin === 'http://localhost:5000' ||
    origin.endsWith('.onrender.com') ||
    origin.endsWith('.accuquote.co.uk');   // update once you have a custom domain

  if (allowed || !origin) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.sendStatus(200); return; }
  next();
});

// ── Service worker: must not be cached ───────────────────────────────────────
app.get('/sw.js', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Service-Worker-Allowed', '/');
  res.sendFile(join(__dirname, '..', 'sw.js'));
});

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Claude proxy ─────────────────────────────────────────────────────────────
app.post('/api/claude', async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'ANTHROPIC_API_KEY not set on server' });
  }

  const { system, userPrompt, maxTokens = 2000 } = req.body || {};
  if (!userPrompt) {
    return res.status(400).json({ error: 'Missing userPrompt' });
  }

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

const ROOT = join(__dirname, '..');

// ── Root route — must come BEFORE express.static ─────────────────────────────
app.get('/', (req, res) => {
  res.sendFile(join(ROOT, 'website.html'));
});

// ── Pre-launch landing page ───────────────────────────────────────────────────
app.get('/prelaunch', (req, res) => {
  res.sendFile(join(ROOT, 'prelaunch.html'));
});

// ── Stripe payment link ───────────────────────────────────────────────────────
app.post('/api/stripe/payment-link', async (req, res) => {
  const stripeKey = process.env.STRIPE_SECRET_KEY;
  if (!stripeKey) {
    return res.status(500).json({ error: 'STRIPE_SECRET_KEY not set on server' });
  }

  const { depositAmount, customerName, jobDescription, traderName } = req.body || {};
  if (!depositAmount || isNaN(depositAmount) || depositAmount <= 0) {
    return res.status(400).json({ error: 'Invalid depositAmount' });
  }

  // AccuQuote takes 1% — Stripe receives the full amount and we use
  // application_fee_amount (requires Connect). For now we add 1% to the
  // charge and note it in the product description. When Connect is set up,
  // swap to application_fee_amount.
  const depositPence    = Math.round(depositAmount * 100);  // customer pays this
  const servicePence    = Math.round(depositAmount * 0.01 * 100);  // 1% fee in pence

  const description = [
    jobDescription ? `Job: ${jobDescription}` : null,
    `Deposit request via AccuQuote`,
    traderName ? `Trader: ${traderName}` : null,
  ].filter(Boolean).join(' · ');

  try {
    // 1. Create a Price (one-off)
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
        'product_data[description]': description,
      }),
    });

    if (!priceRes.ok) {
      const err = await priceRes.json();
      return res.status(500).json({ error: err.error?.message || 'Stripe price error' });
    }
    const price = await priceRes.json();

    // 2. Create a Payment Link
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

    if (!linkRes.ok) {
      console.error('Stripe payment link error:', JSON.stringify(linkBody));
      return res.status(500).json({ error: linkBody.error?.message || 'Stripe link error' });
    }

    if (!linkBody.url) {
      console.error('Stripe response missing url:', JSON.stringify(linkBody));
      return res.status(500).json({ error: 'Stripe did not return a payment URL' });
    }

    res.json({
      url: linkBody.url,
      depositAmount: depositAmount,
      serviceFee: servicePence / 100,
    });
  } catch (err) {
    console.error('Stripe endpoint error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Beehiiv subscribe proxy ───────────────────────────────────────────────────
app.post('/api/subscribe', async (req, res) => {
  const apiKey = process.env.BEEHIIV_API_KEY;
  const pubId  = process.env.BEEHIIV_PUBLICATION_ID;

  if (!apiKey || !pubId) {
    return res.status(500).json({ error: 'Beehiiv credentials not configured' });
  }

  const { email, trade } = req.body || {};
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: 'Invalid email' });
  }

  try {
    const response = await fetch(`https://api.beehiiv.com/v2/publications/${pubId}/subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        email,
        utm_source: 'prelaunch',
        utm_medium: 'organic',
        custom_fields: trade ? [{ name: 'trade', value: trade }] : [],
        send_welcome_email: true,
        reactivate_existing: false,
      }),
    });

    const data = await response.json();

    if (response.status === 201 || response.status === 200) {
      return res.json({ ok: true });
    }

    // Already subscribed
    if (response.status === 409 || data?.errors?.find?.(e => e.includes('already'))) {
      return res.status(409).json({ error: 'already_subscribed' });
    }

    return res.status(response.status).json({ error: data?.message || 'Beehiiv error' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Serve static files (js, css, images, other .html pages) ──────────────────
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

// ── Explicit routes for all HTML pages (ensures no-cache headers always fire) ─
const pages = ['demo', 'blog', 'how-it-works', 'referral', 'quote-cost-calculator', 'privacy-policy'];
pages.forEach(page => {
  app.get(`/${page}`, (req, res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.sendFile(join(ROOT, `${page}.html`));
  });
  app.get(`/${page}.html`, (req, res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.sendFile(join(ROOT, `${page}.html`));
  });
});

// ── Fallback — unmatched routes serve website.html ───────────────────────────
app.get('*', (req, res) => {
  res.sendFile(join(ROOT, 'website.html'));
});

app.listen(PORT, () => {
  console.log(`AccuQuote server running on port ${PORT}`);
});
