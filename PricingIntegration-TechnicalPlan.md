# AccuQuote — Real Supplier Pricing: Technical Implementation Plan

Grounded in: `worker/price-proxy/` (existing, unwired, scrape-based — to be replaced, not extended), `server/index.js`'s `/api/quote/section` (where Claude currently invents SKU/price from training data with no real data source at all), and 13 "live prices" claims across `website.html` (hero, feature sections, pricing cards, FAQ, and three testimonials).

This plan has three phases matching the earlier research: **Phase 0 (immediate)** — stop overclaiming; **Phase 1 (near-term)** — build the real Awin-feed pricing engine; **Phase 2 (long-term)** — extend coverage to trade-gated suppliers.

---

## Phase 0 — Immediate: fix the marketing claim

**Goal:** stop advertising "live" pricing from suppliers the app doesn't actually query, before this is publicly launched. Pure content edit, no backend dependency — ships today regardless of Phase 1/2 timeline.

### Scope: every hit in `website.html`

| Line | Current | Fix |
|---|---|---|
| 7, 17 | meta/OG description: "real supplier prices" | Keep — "real" is defensible once Phase 1 ships (Awin is real trade pricing); true today only if softened further, see note below |
| 508 | hero stat: "live prices, learns how you work" | → "real trade prices, learns how you work" |
| 550 | "labour, materials and live prices" | → "labour, materials and real trade prices" |
| 573 | "Live pricing from Screwfix, Toolstation and CEF — no guessing" | → "Real UK trade prices, refreshed daily from major suppliers — no guessing" (drop named suppliers until Phase 1 confirms which are actually live — see Phase 1 supplier gating below) |
| 613 | "Exact quantities, live prices" | → "Exact quantities, real trade prices" |
| 634 | "priced live against Screwfix and CEF" | → "priced against real UK trade prices" (CEF is Phase 2 — don't name it until it's covered) |
| 696, 756 (pricing cards) | "Live prices — Screwfix, Toolstation, CEF" | → "Real UK trade prices, refreshed daily" |
| 787 | testimonial (Gary, decorator): "Live prices, proper numbers" | → "Real prices, proper numbers" — or cut the phrase if the quote reads fine without it |
| 861 | FAQ: "pulls live pricing from Screwfix, Toolstation and CEF... updated regularly... match materials to real SKUs" | Full rewrite — see below |
| 933, 978, 1013 | three testimonials naming specific suppliers ("Screwfix prices pulled in automatically", "costs pulled from Screwfix", "Toolstation costs pulled live") | **These are the highest-risk lines** — they assert a specific technical behavior in a first-person customer quote. Until Phase 1 ships for that specific supplier, these are fabricated claims in the same category the referral.html leaderboard was. Either (a) genericize to "material costs pulled in automatically" with no named supplier, or (b) hold these three testimonials back entirely until Phase 1 ships and the named supplier is genuinely covered |
| 1045 | "materials and live prices sorted" | → "materials and real trade prices sorted" |

**FAQ rewrite (line 861)** — this is the one place making a factual technical claim outside marketing-speak, so it should describe the actual current mechanism honestly:

> "AccuQuote prices materials against real UK trade costs. Where we have a live feed from a supplier, pricing reflects what's in stock today; everywhere else, pricing is estimated from current market rates and clearly marked as an estimate. We're expanding live supplier coverage — see [status page / in-app note] for what's live right now."

This is the only line that needs to stay accurate *as coverage changes* — see the "supplier gating" mechanism in Phase 1, which this FAQ line should reference once it exists.

**Action:** single-session content edit across `website.html`. No user testing needed beyond a visual proofread. Ship independently of Phase 1/2 — do not wait.

---

## Phase 1 — Near-term: real pricing via Awin feeds

**Goal:** replace AI-guessed material pricing with real, daily-refreshed trade prices for the suppliers where a legitimate data path exists (Toolstation, Wickes, B&Q TradePoint confirmed open; Screwfix pending re-application), with a clearly-labeled AI-estimate fallback for everything else.

### 1.1 — Architecture overview

```
Awin feed (CSV, per supplier)
        │  daily cron
        ▼
Cloudflare Worker (repurposed price-proxy)
  — downloads feed, normalizes, upserts
        ▼
Cloudflare D1 (new) — products table
        │  read at quote-generation time
        ▼
server/index.js /api/quote/section
  — pre-fetch candidate products for the section's trade
  — inject as grounding context into the Claude prompt
  — Claude selects/matches; server tags each item real vs estimated
        ▼
iOS app — QuoteModels.swift gains a `priceSource` field
  — ResultView/QuoteView render a "real price" vs "estimated" badge
```

Key design decision: **Claude does not fetch prices itself.** It has no live tool-use path to the product DB in this flow (the `/api/quote/section` call is a single streaming completion, not an agentic loop with tools). So the server must pre-select relevant real products and hand them to Claude as grounding text in the prompt, and Claude's job shifts from "invent a plausible SKU and price" to "pick the closest real product from this list, or estimate if nothing matches." This is a meaningfully different prompt design, not just a data plumbing change — detailed in 1.4.

### 1.2 — Data layer: Cloudflare D1

Why D1 over KV: pricing data is relational (supplier, category, price, stock, SKU) and needs fuzzy/category-scoped lookups at quote time ("find electrical cable products"), not simple key-value gets. D1 is SQLite at the edge, already in the Cloudflare ecosystem the worker lives in, free tier is generous for this volume (tens of thousands of rows, refreshed daily).

```sql
-- migrations/0001_init.sql
CREATE TABLE products (
  id TEXT PRIMARY KEY,              -- supplier:ean or supplier:product_id, stable across refreshes
  supplier TEXT NOT NULL,           -- 'toolstation' | 'wickes' | 'bq_tradepoint' | 'screwfix'
  name TEXT NOT NULL,
  category TEXT,                    -- Awin feed's merchant_category, used for coarse filtering
  ean TEXT,
  mpn TEXT,
  price_pence INTEGER NOT NULL,     -- VAT-inclusive, from Awin `price` field, stored as integer pence
  in_stock INTEGER NOT NULL,        -- 0/1
  stock_quantity INTEGER,
  deep_link TEXT NOT NULL,          -- Awin affiliate link — also the revenue mechanism
  last_updated TEXT NOT NULL        -- ISO8601, from Awin feed's last_updated
);

CREATE INDEX idx_products_supplier_category ON products(supplier, category);
CREATE INDEX idx_products_name ON products(name);  -- for a future FTS upgrade if simple LIKE isn't enough
```

`id` must be deterministic across daily refreshes (not an auto-increment) so the daily upsert is a true upsert, not a delete-and-reinsert that would momentarily empty the table mid-refresh.

### 1.3 — Worker: feed ingestion (replaces the scraper entirely)

Repurpose `worker/price-proxy/` — same repo location, same deploy target, completely different `src/index.js`. Delete the four `fetchScrewfix`/`fetchToolstation`/`fetchCEF`/`fetchTravisPerkins` scraper functions; replace with:

```js
// worker/price-proxy/src/refresh.js (new)
// Triggered by Cloudflare Cron Trigger, once daily (off-peak, e.g. 03:00 UTC)

const FEEDS = {
  toolstation:   { url: env.AWIN_FEED_URL_TOOLSTATION },
  wickes:        { url: env.AWIN_FEED_URL_WICKES },
  bq_tradepoint: { url: env.AWIN_FEED_URL_BQ_TRADEPOINT },
  // screwfix: added once re-application is approved (see 1.6)
};

export default {
  async scheduled(event, env, ctx) {
    for (const [supplier, { url }] of Object.entries(FEEDS)) {
      ctx.waitUntil(refreshSupplier(supplier, url, env.DB));
    }
  },
};

async function refreshSupplier(supplier, feedUrl, db) {
  const resp = await fetch(feedUrl); // Awin feed URLs embed the API key — treat as secret
  const csv = await resp.text();
  const rows = parseCsv(csv); // Awin feeds are CSV or XML depending on config — pick CSV at setup for simplicity

  const stmt = db.prepare(`
    INSERT INTO products (id, supplier, name, category, ean, mpn, price_pence, in_stock, stock_quantity, deep_link, last_updated)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    ON CONFLICT(id) DO UPDATE SET
      name=excluded.name, category=excluded.category, price_pence=excluded.price_pence,
      in_stock=excluded.in_stock, stock_quantity=excluded.stock_quantity,
      deep_link=excluded.deep_link, last_updated=excluded.last_updated
  `);

  const batch = rows.map(r => stmt.bind(
    `${supplier}:${r.ean || r.product_id}`, supplier, r.product_name, r.merchant_category,
    r.ean, r.mpn, Math.round(parseFloat(r.search_price) * 100),
    r.in_stock === 'yes' ? 1 : 0, parseInt(r.stock_quantity) || null,
    r.aw_deep_link, r.last_updated,
  ));
  await db.batch(batch); // D1 batch — atomic-ish, avoids one-row-per-request round trips
}
```

`wrangler.toml` additions:

```toml
[triggers]
crons = ["0 3 * * *"]  # daily 03:00 UTC

[[d1_databases]]
binding = "DB"
database_name = "accuquote-pricing"
database_id = "<created via wrangler d1 create>"
```

Awin feed URLs (which embed your publisher API key) go in as Worker secrets (`wrangler secret put AWIN_FEED_URL_TOOLSTATION`), never committed to the repo — same discipline already used for `STRIPE_SECRET_KEY` etc. in `server/index.js`.

### 1.4 — Query endpoint: worker exposes a lookup, server calls it

Keep the existing `GET /price?q=...` shape from the old worker (server/index.js and the iOS app never called it, so nothing depends on the old contract) but change what it does: query D1 instead of live-scraping.

```js
// worker/price-proxy/src/index.js (fetch handler, kept alongside the new scheduled handler)
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const q = url.searchParams.get('q');
    const category = url.searchParams.get('category'); // optional coarse filter
    if (!q) return json({ error: 'Missing ?q=' }, 400);

    const results = await env.DB.prepare(`
      SELECT supplier, name, price_pence, in_stock, deep_link, ean
      FROM products
      WHERE name LIKE ?1 ${category ? 'AND category = ?2' : ''}
      ORDER BY in_stock DESC, price_pence ASC
      LIMIT 8
    `).bind(`%${q}%`, ...(category ? [category] : [])).all();

    return json({ query: q, results: results.results, checkedAt: new Date().toISOString() });
  },
  scheduled, // from refresh.js
};
```

### 1.5 — `server/index.js` integration: `/api/quote/section`

This is the actual behavior change users will see. Before building the prompt (around line 779), pre-fetch a candidate product list for the section being priced and inject it as grounding, then post-process Claude's output to tag each item.

```js
// New helper, near the top of the quote-generation section
async function fetchPriceCandidates(sectionLabel, tradeScope) {
  const priceProxyUrl = process.env.PRICE_PROXY_URL; // e.g. https://price-proxy.accuquote.workers.dev
  if (!priceProxyUrl) return [];
  try {
    const q = `${sectionLabel} ${tradeScope || ''}`.trim();
    const res = await fetch(`${priceProxyUrl}/price?q=${encodeURIComponent(q)}`, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) return [];
    const data = await res.json();
    return data.results || [];
  } catch {
    return []; // pricing lookup is best-effort — never block quote generation on it
  }
}
```

Prompt change (replaces the single "Match materials to REAL products" line at 790):

```js
const candidates = await fetchPriceCandidates(safeSection, safeScope);
const candidateBlock = candidates.length
  ? `REAL PRODUCT PRICES AVAILABLE (use these exact prices/SKUs when a listed product matches what's needed — set "priceSource":"real" for those items):\n` +
    candidates.map(c => `- ${c.name} | £${(c.price_pence / 100).toFixed(2)} | SKU ${c.ean || 'n/a'} | ${c.supplier} | ${c.in_stock ? 'in stock' : 'out of stock'}`).join('\n') + '\n\n'
  : '';

const prompt = `${safeCtx ? safeCtx + '\n\n' : ''}` +
  `<JOB>\n${safeJob}\n</JOB>\n\n` +
  `SECTION TO PRICE: ${safeSection}\nSCOPE: ${safeScope}\n\n` +
  `ROOM: ${rd.roomType || ''}\n...` +
  candidateBlock +
  `PREFERRED SUPPLIER: ${safeSupplier}\n` +
  `${safeItems ? 'PRODUCTS THEY REGULARLY ORDER: ' + safeItems + '\n' : ''}` +
  `\nPrice ONLY the '${safeSection}' scope. Be exhaustive.\n` +
  `For any item matching a product in REAL PRODUCT PRICES, use that exact price and set "priceSource":"real". ` +
  `For anything not listed there, estimate a realistic current UK trade price and set "priceSource":"estimated".\n\n` +
  `OUTPUT: Return ONLY a single raw JSON object — no markdown, no prose.\n` +
  `Schema: {"labourDays":2.0,"labourRate":280.0,"items":[{"description":"...","qty":1.0,"unit":"each","unitPrice":12.50,"sku":"123456","supplier":"...","priceSource":"real|estimated"}],"vatRate":20,"notes":"..."}\n` +
  `No item cap. Keep descriptions under 70 chars.`;
```

`PRICE_PROXY_URL` joins the existing env-var-driven config pattern (add to the top-of-file doc comment and `.env.example` alongside `STRIPE_SECRET_KEY` etc.). The fetch has a 3s timeout and fails open to empty candidates — a price-proxy outage must never block or slow quote generation meaningfully, it should just silently fall back to full AI estimation exactly as today.

### 1.6 — Supplier onboarding checklist (do before any code ships)

1. Register a free Awin publisher account for AccuQuote.
2. Apply to the **Toolstation**, **Wickes**, and **B&Q TradePoint** affiliate programs (all confirmed open per research).
3. Email `affiliates@screwfix.com` directly requesting program access for a legitimate SaaS integration — their public program is closed to new applicants but this doesn't mean unreachable; worth a direct ask given AccuQuote's use case.
4. Once approved per-supplier, generate feed URLs from Awin's publisher dashboard (`productdata.awin.com/datafeed/list/apikey/...`), store each as a Worker secret.
5. **Gate the `FEEDS` object in the worker to only suppliers actually approved** — do not silently add a supplier's data source before their Awin approval lands, and do not let `website.html`'s copy (which should stay generic, per Phase 0) get supplier names re-added until each is live.

### 1.7 — iOS changes

`Quote/QuoteModels.swift`'s `SavedQuoteItem`/`QuoteLineItem` (and the ephemeral in-flight quote item type used during streaming) need a new field:

```swift
var priceSource: String  // "real" | "estimated" — default "estimated" for backwards-compat decode of old saved quotes
```

`Results/ResultView.swift` / `Results/ResultComponents.swift` (line-item rendering) gets a small badge/label — e.g. a green "live" tag next to real-priced items, nothing on estimated ones (estimated is the default expectation, not a flaw to flag loudly — matches the house convention of not showing negative/technical detail to users unless it changes what they should do).

This is a genuinely new field flowing through the whole pipeline (server → SSE stream → `QuoteGenerationService.swift` parsing → `QuoteModels` → persisted `SavedQuote` → rendered UI), so needs the same `Codable` backwards-compatibility treatment already used for `scanMode`/`scanArtifactURL` in `QuoteHistory.swift` (optional decode, default value for old saved quotes that predate the field).

### 1.8 — Testing plan

- Worker: `wrangler dev` locally against a small hand-written CSV fixture (not a live Awin feed) to verify the upsert logic and query endpoint independently of any real account being approved yet.
- Server: unit-test `fetchPriceCandidates`'s fail-open behavior (worker down/slow/malformed response → empty array, quote generation proceeds unaffected) — this is the one behavior that must never regress, since a bug here would make pricing lookups block real quote generation.
- End-to-end: once at least one supplier's feed is live, generate a real quote for a job type known to hit that supplier's catalog (e.g. Toolstation for cabling) and manually confirm the returned price matches Toolstation's current site price and the `priceSource` badge renders correctly.
- Re-run the FAQ copy check from Phase 0 once a supplier goes live — that's the trigger to re-add that supplier's name to the marketing copy, not before.

### 1.9 — Rollout order

1. Ship worker rewrite (D1 schema + scheduled refresh + query endpoint), deployed but not yet called by `server/`, verified via manual `curl` against the price-proxy URL.
2. Wire `server/index.js` integration behind `PRICE_PROXY_URL` being unset by default in production until step 1 is confirmed stable for a few days of cron runs.
3. Set `PRICE_PROXY_URL`, ship iOS `priceSource` support, re-test end-to-end.
4. Only then, re-add the specific approved supplier's name to `website.html` copy (Phase 0's FAQ rewrite explicitly deferred this).

---

## Phase 2 — Long-term: trade-gated suppliers (CEF, Selco, Travis Perkins)

**Goal:** extend real-pricing coverage to the suppliers with no public feed, once Phase 1's value is proven (real usage data, or explicit user demand for those specific suppliers).

No code should be written for this phase until Phase 1 is live and its actual adoption/impact is known — this section is a decision framework, not a build spec.

### 2.1 — Option A: open a trade account per supplier

CEF and Selco both gate pricing behind a trade account. AccuQuote (the business) could open trade accounts with each, which would grant access to that supplier's own account portal pricing (their genuine current trade price, not a public feed). This requires:
- A defined process for periodically exporting/syncing that account's price list into the same `products` D1 table (same schema Phase 1 established — this is additive, not a redesign).
- Legal/ToS review specific to each supplier's trade account terms — most trade accounts are between the supplier and the *account holder* for the account holder's own purchasing, not for redistribution inside a third-party product; this needs explicit confirmation from each supplier before building, not an assumption.

### 2.2 — Option B: revisit HBXL or a similar aggregator

HBXL's "Price Tracker+" (referenced in the research) already solves "current UK merchant pricing" as a licensable data problem for the construction-estimating market. Worth a direct commercial enquiry once Phase 1's usage data makes the ROI case concrete — likely a per-seat or data-license cost that only makes sense at a certain user volume.

### 2.3 — Trigger to revisit

Track (via `FunnelAnalytics`/server logging, already in place elsewhere in this codebase) how often generated quotes reference CEF/Selco/Travis-Perkins-typical categories (electrical wholesale, heavy building materials) with `priceSource: "estimated"`. If that's a small minority of quote volume, Phase 2 is low-priority. If it's a large share (e.g. electrical trades leaning heavily on CEF-typical items), that's the concrete signal to prioritize Option A for that specific supplier first.

---

## Summary of what ships when

| Phase | What | Depends on |
|---|---|---|
| 0 | Rewrite 13 "live prices" claims in `website.html` to accurate copy | Nothing — ship immediately |
| 1 | Awin publisher signup + 3 supplier applications | Nothing — start immediately, approval takes days-to-weeks |
| 1 | Worker rewrite: D1 schema, scheduled feed ingestion, query endpoint | Awin approval for at least one supplier (can build/test against a fixture before approval lands) |
| 1 | `server/index.js` integration: candidate pre-fetch, prompt change, `priceSource` field | Worker query endpoint live |
| 1 | iOS: `priceSource` field through the model/persistence/UI pipeline | Server integration live |
| 1 | Re-add approved supplier names to marketing copy | Each specific integration verified end-to-end |
| 2 | CEF/Selco/Travis Perkins trade-account or aggregator integration | Phase 1 live + usage data justifying the investment |
