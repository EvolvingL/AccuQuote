/**
 * AccuQuote Price Proxy — Cloudflare Worker
 *
 * Replaces the old scrape-based proxy entirely (see git history) with real
 * Awin affiliate feed data stored in D1, per PricingIntegration-TechnicalPlan.md.
 *
 * Runs on the Workers Paid plan ($5/month, upgraded 2026-09-22) — needed
 * because a full Awin catalog feed (tens of thousands of rows) can't be
 * parsed and upserted within the free plan's 10ms CPU cap per invocation.
 * Paid raises that to 30s by default (see wrangler.toml's [limits]).
 *
 * - Daily cron ingests each approved supplier's whole Awin feed into D1 in
 *   one pass (refresh.js)
 * - GET /price?q=<term>&category=<optional> — queries D1 for candidate products
 * - POST /admin/refresh?supplier=<name>&secret=<ADMIN_SECRET> — manual
 *   trigger, same path the cron uses (or ingests a raw CSV body directly,
 *   for testing against a small fixture)
 * - GET /admin/peek?supplier=<name>&secret=<ADMIN_SECRET> — debug: returns
 *   just the header + first 2 data rows of a real feed, to check its shape
 *   without pulling/logging the whole catalog
 */
import { scheduled, refreshSupplier, ingestCsv, maybeDecompress } from './refresh.js';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
};

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === '/admin/refresh' && request.method === 'POST') {
      return handleAdminRefresh(request, env);
    }

    if (url.pathname === '/admin/peek' && request.method === 'GET') {
      return handleAdminPeek(url, env);
    }

    if (url.pathname === '/price') {
      return handlePriceQuery(url, env);
    }

    return json({ error: 'Not found' }, 404);
  },
  scheduled,
};

// Common connector/filler words that add noise, not signal, to a product
// name match — dropped before building the query so "twin and earth cable"
// searches for {twin, earth, cable}, not {twin, and, earth, cable} (which
// would spuriously require the literal word "and" in the product name).
const STOPWORDS = new Set(['and', 'the', 'a', 'an', 'for', 'of', 'with', 'to', 'in', 'on']);

function significantWords(q) {
  return q
    .toLowerCase()
    .split(/\s+/)
    .map(w => w.trim())
    .filter(w => w.length > 1 && !STOPWORDS.has(w));
}

// Word-level AND matching, not whole-phrase substring matching. A caller
// searching for "twin and earth cable" needs a hit on a product named
// "4TRADE 6242YH 2.5mm Twin & Earth Cable Grey 50m" — the whole phrase
// never appears verbatim (different connector, ampersand vs "and", extra
// words in between), but every significant word does. Confirmed live
// against the real Travis Perkins catalog (2026-09-26): whole-phrase
// matching returned 0 results for "twin and earth cable", "consumer unit"-
// shaped multi-word terms, etc.; word-level AND matching recovers the
// former while still correctly returning nothing for genuine catalog gaps
// (e.g. "socket" AND "faceplate" — confirmed no such product in the feed).
// See PricingIntegration-TechnicalPlan.md §1.4/§1.5 and the two-pass
// materials-extraction change in server/index.js's fetchPriceCandidates.
async function handlePriceQuery(url, env) {
  const q = url.searchParams.get('q');
  const category = url.searchParams.get('category'); // optional coarse filter
  if (!q) return json({ error: 'Missing ?q=' }, 400);
  if (!env.DB) return json({ error: 'Database not configured' }, 500);

  const words = significantWords(q);
  if (!words.length) return json({ query: q, results: [], checkedAt: new Date().toISOString() });

  // Cap word count so a very long query can't build an unbounded WHERE
  // clause — 6 significant words is already a very specific search.
  const boundedWords = words.slice(0, 6);
  const whereClauses = boundedWords.map((_, i) => `name LIKE ?${i + 1}`).join(' AND ');
  const binds = boundedWords.map(w => `%${w}%`);
  const categoryClause = category ? ` AND category = ?${boundedWords.length + 1}` : '';
  if (category) binds.push(category);

  const results = await env.DB.prepare(`
    SELECT supplier, name, price_pence, in_stock, deep_link, ean
    FROM products
    WHERE ${whereClauses}${categoryClause}
    ORDER BY in_stock DESC, price_pence ASC
    LIMIT 8
  `).bind(...binds).all();

  return json({ query: q, results: results.results, checkedAt: new Date().toISOString() });
}

// Manual trigger for testing a single supplier's ingestion without waiting
// for the daily cron — requires ADMIN_SECRET (same discipline as
// server/index.js's /api/admin/* routes). Runs the same single-shot
// fetch+decompress+parse+upsert path the cron uses. A raw CSV body
// (Content-Type: text/csv or text/plain) instead ingests that text directly
// — for testing against a small fixture without needing a live feed URL.
async function handleAdminRefresh(request, env) {
  const url = new URL(request.url);
  const secret = url.searchParams.get('secret');
  if (!env.ADMIN_SECRET || secret !== env.ADMIN_SECRET) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const supplier = url.searchParams.get('supplier');
  if (!supplier) return json({ error: 'Missing ?supplier=' }, 400);
  if (!env.DB) return json({ error: 'Database not configured' }, 500);

  try {
    const contentType = request.headers.get('content-type') || '';
    if (contentType.includes('text/csv') || contentType.includes('text/plain')) {
      const csv = await request.text();
      const result = await ingestCsv(supplier, csv, env.DB);
      return json(result);
    }

    const feedUrlKey = `AWIN_FEED_URL_${supplier.toUpperCase()}`;
    const feedUrl = env[feedUrlKey];
    if (!feedUrl) return json({ error: `No feed URL configured for ${supplier} (expected secret ${feedUrlKey})` }, 400);

    const result = await refreshSupplier(supplier, feedUrl, env.DB);
    return json(result);
  } catch (err) {
    return json({ error: err.message }, 500);
  }
}

// Debug-only: returns just the header row + first 2 data rows of a real
// feed, so a header/column mismatch can be diagnosed without pulling or
// logging the whole catalog. Same ADMIN_SECRET gate as the other admin
// routes.
async function handleAdminPeek(url, env) {
  const secret = url.searchParams.get('secret');
  if (!env.ADMIN_SECRET || secret !== env.ADMIN_SECRET) {
    return json({ error: 'Unauthorized' }, 401);
  }
  const supplier = url.searchParams.get('supplier');
  if (!supplier) return json({ error: 'Missing ?supplier=' }, 400);

  const feedUrlKey = `AWIN_FEED_URL_${supplier.toUpperCase()}`;
  const feedUrl = env[feedUrlKey];
  if (!feedUrl) return json({ error: `No feed URL configured for ${supplier}` }, 400);

  try {
    const resp = await fetch(feedUrl);
    if (!resp.ok) return json({ error: `Feed fetch failed: HTTP ${resp.status}` }, 502);

    const body = await maybeDecompress(resp);
    const text = await new Response(body).text();
    const firstLines = text.split('\n').slice(0, 3);
    return json({ supplier, contentType: resp.headers.get('content-type'), firstLines });
  } catch (err) {
    return json({ error: err.message }, 500);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS_HEADERS });
}
