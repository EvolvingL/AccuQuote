// AccuQuote Price Proxy — feed ingestion (Cloudflare Cron Trigger, daily)
// See PricingIntegration-TechnicalPlan.md §1.3.
//
// Single-invocation streaming ingestion: fetch the feed, decompress if
// needed, and parse+upsert it incrementally as it streams in — never
// holding the whole feed text, the whole parsed row set, or one giant D1
// batch in memory at once. Runs to completion in one Worker invocation.
//
// Two separate limits shaped this design, both hit in production on
// 2026-09-21/22 while ingesting Travis Perkins' real feed (tens of
// thousands of rows):
//   1. CPU time: the free plan's 10ms-per-invocation cap can't fit
//      parsing+upserting a full feed ("Worker exceeded CPU time limit" /
//      error 1102). Fixed by upgrading to Workers Paid ($5/month,
//      2026-09-22), which raises this to 30s by default (see
//      wrangler.toml's [limits]).
//   2. Memory: reading the whole decompressed feed into one string via
//      `.text()`, building the whole parsed-row array, and building one
//      D1 batch() call for every row — all at once — blew the 128MB
//      per-invocation memory limit ("Worker exceeded memory limit"), which
//      is NOT a plan-tier setting; it applies regardless of plan. Fixed by
//      streaming: read the response body incrementally, parse one CSV line
//      at a time, and flush to D1 in small batches as rows accumulate,
//      so peak memory stays bounded by one buffer + one batch, not the
//      whole feed.
//
// (An earlier version of this file also tried chunked self-chaining ingest
// across multiple invocations with a KV-backed feed cache, to work around
// the free-tier CPU cap without paying for Workers Paid. That approach is
// removed — streaming within one paid-tier invocation is simpler and this
// is faster overall once CPU isn't the constraint.)
import { parseCsvLines, rowsToObjects } from './csv.js';

const D1_BATCH_SIZE = 500; // rows per D1 batch() call — keeps each batch small regardless of total feed size

// Awin lets each publisher choose a delimiter per datafeed at setup time.
// Confirmed live that Travis Perkins' feed is standard comma-delimited CSV
// with quoted fields. Override per-supplier here only if a future feed is
// confirmed otherwise (check with /admin/peek).
const DELIMITERS = {};
function delimiterFor(supplier) {
  return DELIMITERS[supplier] || ',';
}

// Awin serves at least some feeds (confirmed: Travis Perkins) as gzip —
// Content-Type: application/gzip, actual gzip bytes in the body, not just
// Content-Encoding: gzip (which fetch() would auto-decompress transparently;
// this is the case where the caller must decompress explicitly). Detect via
// Content-Type first, falling back to the gzip magic bytes (1f 8b) by
// peeking the first two bytes of the stream, so a plain-text feed with a
// wrong/missing Content-Type still gets read correctly either way.
export async function maybeDecompress(resp) {
  const contentType = (resp.headers.get('content-type') || '').toLowerCase();
  if (contentType.includes('gzip')) {
    return resp.body.pipeThrough(new DecompressionStream('gzip'));
  }

  const [peekable, passthrough] = resp.body.tee();
  const reader = peekable.getReader();
  const { value: firstChunk } = await reader.read();
  reader.cancel();

  const isGzipMagic = firstChunk && firstChunk.length >= 2 && firstChunk[0] === 0x1f && firstChunk[1] === 0x8b;
  if (isGzipMagic) {
    return passthrough.pipeThrough(new DecompressionStream('gzip'));
  }
  return passthrough;
}

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
  for (const supplier of Object.keys(feeds)) {
    ctx.waitUntil(refreshSupplier(supplier, feeds[supplier], env.DB));
  }
}

// Fetches, decompresses if needed, and streams a supplier's whole feed
// straight into D1 — parsing and upserting incrementally so peak memory
// stays bounded regardless of total feed size (see file header).
export async function refreshSupplier(supplier, feedUrl, db) {
  const resp = await fetch(feedUrl); // Awin feed URLs embed the API key — treat as secret
  if (!resp.ok) throw new Error(`Feed fetch failed for ${supplier}: HTTP ${resp.status}`);
  const body = await maybeDecompress(resp);
  return ingestStream(supplier, body, db, delimiterFor(supplier));
}

// Reads a decompressed feed body incrementally: decodes bytes as they
// arrive, splits into complete CSV lines (tracking quote state across chunk
// boundaries so a quoted field containing a literal newline isn't split
// mid-field), and upserts each accumulated batch of D1_BATCH_SIZE rows to
// D1 before continuing — so only one batch's worth of parsed rows and one
// chunk's worth of raw text are ever held at once, not the whole feed.
export async function ingestStream(supplier, body, db, delimiter = ',') {
  const reader = body.getReader();
  const decoder = new TextDecoder();

  let buffer = '';
  let inQuotes = false;
  let header = null;
  let pendingRows = [];
  let rowsIngested = 0;
  let rowsSkipped = 0;

  const flushRows = async () => {
    if (!pendingRows.length) return;
    const objs = rowsToObjects(header, pendingRows);
    const result = await upsertBatch(supplier, objs, db);
    rowsIngested += result.rowsIngested;
    rowsSkipped += result.rowsSkipped;
    pendingRows = [];
  };

  const consumeLine = async (line) => {
    if (!line.length) return; // skip blank lines
    const fields = parseCsvLines(line, delimiter)[0] || [];
    if (!header) {
      header = fields; // first non-empty line is the header
      return;
    }
    pendingRows.push(fields);
    if (pendingRows.length >= D1_BATCH_SIZE) await flushRows();
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let lineStart = 0;
    for (let i = 0; i < buffer.length; i++) {
      const c = buffer[i];
      if (c === '"') inQuotes = !inQuotes;
      else if (c === '\n' && !inQuotes) {
        let line = buffer.slice(lineStart, i);
        if (line.endsWith('\r')) line = line.slice(0, -1);
        await consumeLine(line);
        lineStart = i + 1;
      }
    }
    // Keep only the unconsumed tail in the buffer, so it never grows to
    // hold the whole feed — just whatever's left after the last full line
    // in the chunks read so far.
    buffer = buffer.slice(lineStart);
  }
  buffer += decoder.decode(); // flush any trailing multi-byte sequence
  if (buffer.length) {
    let line = buffer;
    if (line.endsWith('\r')) line = line.slice(0, -1);
    await consumeLine(line);
  }
  await flushRows();

  return { supplier, rowsIngested, rowsSkipped };
}

async function upsertBatch(supplier, rows, db) {
  const stmt = db.prepare(`
    INSERT INTO products (id, supplier, name, category, ean, mpn, price_pence, in_stock, stock_quantity, deep_link, last_updated)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    ON CONFLICT(id) DO UPDATE SET
      name=excluded.name, category=excluded.category, price_pence=excluded.price_pence,
      in_stock=excluded.in_stock, stock_quantity=excluded.stock_quantity,
      deep_link=excluded.deep_link, last_updated=excluded.last_updated
  `);

  const batch = [];
  let rowsSkipped = 0;
  for (const r of rows) {
    const productKey = r.ean || r.merchant_product_id || r.aw_product_id;
    if (!productKey || !r.product_name || !r.search_price) { rowsSkipped++; continue; } // skip malformed rows rather than fail the whole refresh

    const pricePence = Math.round(parseFloat(r.search_price) * 100);
    if (!Number.isFinite(pricePence)) { rowsSkipped++; continue; }

    // Not every Awin feed includes an in_stock column at all — confirmed
    // live that Travis Perkins' feed has no in_stock/stock_quantity fields
    // whatsoever. Treat "field absent" as in-stock (Awin's default listing
    // behavior for feeds without explicit stock data is to list sellable
    // items), and only treat it as out-of-stock when the feed explicitly
    // says so with a non-"yes" value.
    const inStock = r.in_stock === undefined ? 1 : (r.in_stock.toLowerCase() === 'yes' ? 1 : 0);

    batch.push(stmt.bind(
      `${supplier}:${productKey}`,
      supplier,
      r.product_name,
      r.merchant_category || r.category_name || null,
      r.ean || null,
      r.mpn || null,
      pricePence,
      inStock,
      r.stock_quantity ? parseInt(r.stock_quantity, 10) : null,
      r.aw_deep_link || r.merchant_deep_link,
      r.last_updated || new Date().toISOString(),
    ));
  }

  if (batch.length) await db.batch(batch); // D1 batch — atomic-ish, avoids one-row-per-request round trips
  return { rowsIngested: batch.length, rowsSkipped };
}

// Kept for tests/fixtures/the admin raw-CSV-upload path: parses a whole CSV
// string already in memory. Fine for small fixtures; the real feed path
// (refreshSupplier -> ingestStream) never materializes the whole feed as
// one string — see file header for why that matters.
export async function ingestCsv(supplier, csv, db, delimiter = ',') {
  const rows = parseCsvLines(csv, delimiter);
  const header = rows.shift();
  if (!header) return { supplier, rowsIngested: 0, rowsSkipped: 0 };
  const objs = rowsToObjects(header, rows);
  const result = await upsertBatch(supplier, objs, db);
  return { supplier, ...result };
}
