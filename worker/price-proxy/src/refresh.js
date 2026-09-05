// AccuQuote Price Proxy — feed ingestion (Cloudflare Cron Trigger, daily)
// See PricingIntegration-TechnicalPlan.md §1.3.
import { parseCsv } from './csv.js';

// Only suppliers with an approved Awin feed URL configured go in here.
// Gate strictly — do not add a supplier before their Awin approval lands,
// per the technical plan's §1.6 step 5.
function activeFeeds(env) {
  const feeds = {};
  if (env.AWIN_FEED_URL_TRAVISPERKINS) feeds.travisperkins = env.AWIN_FEED_URL_TRAVISPERKINS;
  if (env.AWIN_FEED_URL_TOOLSTATION)   feeds.toolstation   = env.AWIN_FEED_URL_TOOLSTATION;
  if (env.AWIN_FEED_URL_WICKES)        feeds.wickes        = env.AWIN_FEED_URL_WICKES;
  if (env.AWIN_FEED_URL_BQ_TRADEPOINT) feeds.bq_tradepoint = env.AWIN_FEED_URL_BQ_TRADEPOINT;
  if (env.AWIN_FEED_URL_SCREWFIX)      feeds.screwfix      = env.AWIN_FEED_URL_SCREWFIX;
  return feeds;
}

export async function scheduled(event, env, ctx) {
  const feeds = activeFeeds(env);
  for (const [supplier, url] of Object.entries(feeds)) {
    ctx.waitUntil(refreshSupplier(supplier, url, env.DB));
  }
}

export async function refreshSupplier(supplier, feedUrl, db) {
  const resp = await fetch(feedUrl); // Awin feed URLs embed the API key — treat as secret
  if (!resp.ok) throw new Error(`Feed fetch failed for ${supplier}: HTTP ${resp.status}`);
  const csv = await resp.text();
  return ingestCsv(supplier, csv, db);
}

// Split out from refreshSupplier so tests/local runs can feed it a fixture
// string directly without a real network fetch.
export async function ingestCsv(supplier, csv, db) {
  const rows = parseCsv(csv);

  const stmt = db.prepare(`
    INSERT INTO products (id, supplier, name, category, ean, mpn, price_pence, in_stock, stock_quantity, deep_link, last_updated)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    ON CONFLICT(id) DO UPDATE SET
      name=excluded.name, category=excluded.category, price_pence=excluded.price_pence,
      in_stock=excluded.in_stock, stock_quantity=excluded.stock_quantity,
      deep_link=excluded.deep_link, last_updated=excluded.last_updated
  `);

  const batch = [];
  for (const r of rows) {
    const productKey = r.ean || r.merchant_product_id || r.aw_product_id;
    if (!productKey || !r.product_name || !r.search_price) continue; // skip malformed rows rather than fail the whole refresh

    const pricePence = Math.round(parseFloat(r.search_price) * 100);
    if (!Number.isFinite(pricePence)) continue;

    batch.push(stmt.bind(
      `${supplier}:${productKey}`,
      supplier,
      r.product_name,
      r.merchant_category || r.category_name || null,
      r.ean || null,
      r.mpn || null,
      pricePence,
      (r.in_stock || '').toLowerCase() === 'yes' ? 1 : 0,
      r.stock_quantity ? parseInt(r.stock_quantity, 10) : null,
      r.aw_deep_link || r.merchant_deep_link,
      r.last_updated || new Date().toISOString(),
    ));
  }

  if (batch.length) await db.batch(batch); // D1 batch — atomic-ish, avoids one-row-per-request round trips
  return { supplier, rowsIngested: batch.length, rowsSkipped: rows.length - batch.length };
}
