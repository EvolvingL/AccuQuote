/**
 * AccuQuote Price Proxy — Cloudflare Worker
 *
 * Replaces the old scrape-based proxy entirely (see git history) with real
 * Awin affiliate feed data stored in D1, per PricingIntegration-TechnicalPlan.md.
 *
 * - Daily cron ingests each approved supplier's Awin feed into D1 (refresh.js)
 * - GET /price?q=<term>&category=<optional> — queries D1 for candidate products
 * - POST /admin/refresh?supplier=<name>&secret=<ADMIN_SECRET> — manual trigger,
 *   for testing ingestion before the cron fires, or against a fixture locally
 */
import { scheduled, refreshSupplier, ingestCsv } from './refresh.js';

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

    if (url.pathname === '/price') {
      return handlePriceQuery(url, env);
    }

    return json({ error: 'Not found' }, 404);
  },
  scheduled,
};

async function handlePriceQuery(url, env) {
  const q = url.searchParams.get('q');
  const category = url.searchParams.get('category'); // optional coarse filter
  if (!q) return json({ error: 'Missing ?q=' }, 400);
  if (!env.DB) return json({ error: 'Database not configured' }, 500);

  const results = await env.DB.prepare(`
    SELECT supplier, name, price_pence, in_stock, deep_link, ean
    FROM products
    WHERE name LIKE ?1 ${category ? 'AND category = ?2' : ''}
    ORDER BY in_stock DESC, price_pence ASC
    LIMIT 8
  `).bind(`%${q}%`, ...(category ? [category] : [])).all();

  return json({ query: q, results: results.results, checkedAt: new Date().toISOString() });
}

// Manual trigger for testing a single supplier's ingestion without waiting
// for the daily cron — requires ADMIN_SECRET (same discipline as
// server/index.js's /api/admin/* routes). Also accepts a raw CSV body for
// testing against the fixture without needing a live Awin feed URL yet.
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
    let result;
    if (contentType.includes('text/csv') || contentType.includes('text/plain')) {
      // Fixture/manual CSV upload path — no Awin feed URL required.
      const csv = await request.text();
      result = await ingestCsv(supplier, csv, env.DB);
    } else {
      const feedUrlKey = `AWIN_FEED_URL_${supplier.toUpperCase()}`;
      const feedUrl = env[feedUrlKey];
      if (!feedUrl) return json({ error: `No feed URL configured for ${supplier} (expected secret ${feedUrlKey})` }, 400);
      result = await refreshSupplier(supplier, feedUrl, env.DB);
    }
    return json(result);
  } catch (err) {
    return json({ error: err.message }, 500);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS_HEADERS });
}
