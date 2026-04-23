/**
 * AccuQuote Price Proxy — Cloudflare Worker
 *
 * Fetches live prices from Screwfix, Toolstation, CEF, and Travis Perkins
 * by calling the same internal JSON endpoints their own websites use.
 *
 * Deploy: wrangler deploy
 * Endpoint: GET /price?q=<search+term>&suppliers=screwfix,toolstation,cef,travis
 *
 * Returns:
 * {
 *   query: "2.5mm twin earth",
 *   results: {
 *     screwfix:    { price: 84.99, name: "...", sku: "...", url: "...", inStock: true,  checkedAt: "..." },
 *     toolstation: { price: 82.50, name: "...", sku: "...", url: "...", inStock: true,  checkedAt: "..." },
 *     cef:         { price: null,  error: "not found" },
 *     travis:      { price: 91.00, name: "...", sku: "...", url: "...", inStock: true,  checkedAt: "..." },
 *   }
 * }
 */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
};

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const query = url.searchParams.get('q');
    const suppliersParam = url.searchParams.get('suppliers') || 'screwfix,toolstation,cef,travis';

    if (!query) {
      return json({ error: 'Missing ?q= parameter' }, 400);
    }

    const suppliers = suppliersParam.split(',').map(s => s.trim().toLowerCase());

    // Run all supplier lookups in parallel
    const fetchers = {
      screwfix:    () => fetchScrewfix(query),
      toolstation: () => fetchToolstation(query),
      cef:         () => fetchCEF(query),
      travis:      () => fetchTravisPerkins(query),
    };

    const promises = suppliers
      .filter(s => fetchers[s])
      .map(async s => {
        try {
          const result = await fetchers[s]();
          return [s, result];
        } catch (e) {
          return [s, { price: null, error: e.message }];
        }
      });

    const entries = await Promise.all(promises);
    const results = Object.fromEntries(entries);

    return json({ query, results, checkedAt: new Date().toISOString() });
  }
};

// ─── SCREWFIX ────────────────────────────────────────────────────────────────
// Screwfix exposes a search suggest + product JSON API used by their own site.

async function fetchScrewfix(query) {
  const encoded = encodeURIComponent(query);

  // Their internal search API — returns JSON with product list
  const searchUrl = `https://www.screwfix.com/search?search=${encoded}&inStockOnly=false&sortby=&refinements=&isFiltered=false`;

  const resp = await fetch(searchUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-GB,en;q=0.9',
    },
    cf: { cacheEverything: true, cacheTtl: 300 }, // Cache for 5 minutes
  });

  if (!resp.ok) throw new Error(`Screwfix HTTP ${resp.status}`);

  const html = await resp.text();

  // Screwfix embeds product data as JSON in a <script> tag
  // Pattern: window.__INITIAL_STATE__ = {...}  or  "products":[{...}]
  const stateMatch = html.match(/window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\});<\/script>/);
  if (stateMatch) {
    try {
      const state = JSON.parse(stateMatch[1]);
      const products = state?.searchPage?.products || state?.products?.items || [];
      const first = products[0];
      if (first) {
        return parseScreefixProduct(first);
      }
    } catch (_) {}
  }

  // Fallback: parse structured data from HTML
  return parseScrewfixHTML(html, query);
}

function parseScreefixProduct(p) {
  const price = p.price?.value || p.sellPrice || p.price;
  return {
    price: price ? parseFloat(price) : null,
    name: p.name || p.title,
    sku: p.productCode || p.sku,
    url: `https://www.screwfix.com/p/${p.slug || p.productCode}`,
    inStock: p.stock?.available !== false,
    checkedAt: new Date().toISOString(),
  };
}

function parseScrewfixHTML(html, query) {
  // Try JSON-LD product data
  const jsonLdMatch = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g);
  if (jsonLdMatch) {
    for (const block of jsonLdMatch) {
      try {
        const inner = block.replace(/<script[^>]*>/, '').replace(/<\/script>/, '');
        const data = JSON.parse(inner);
        const items = Array.isArray(data) ? data : [data];
        for (const item of items) {
          if (item['@type'] === 'Product' || item['@type'] === 'ItemList') {
            const product = item['@type'] === 'ItemList' ? item.itemListElement?.[0]?.item : item;
            if (product) {
              const offer = product.offers || product.offer;
              const price = offer?.price || offer?.lowPrice;
              return {
                price: price ? parseFloat(price) : null,
                name: product.name,
                sku: product.sku || product.mpn,
                url: product.url,
                inStock: offer?.availability !== 'OutOfStock',
                checkedAt: new Date().toISOString(),
              };
            }
          }
        }
      } catch (_) {}
    }
  }

  // Last resort: regex price extraction
  const priceMatch = html.match(/["']price["']\s*:\s*["']?([\d.]+)["']?/);
  const nameMatch = html.match(/<h1[^>]*class="[^"]*product[^"]*"[^>]*>([^<]+)<\/h1>/i);
  if (priceMatch) {
    return {
      price: parseFloat(priceMatch[1]),
      name: nameMatch ? nameMatch[1].trim() : query,
      sku: null,
      url: `https://www.screwfix.com/search?search=${encodeURIComponent(query)}`,
      inStock: null,
      checkedAt: new Date().toISOString(),
    };
  }

  throw new Error('Could not parse Screwfix response');
}

// ─── TOOLSTATION ─────────────────────────────────────────────────────────────
// Toolstation has a clean internal search API that returns JSON

async function fetchToolstation(query) {
  const encoded = encodeURIComponent(query);

  // Toolstation's search endpoint returns structured JSON
  const apiUrl = `https://www.toolstation.com/search?q=${encoded}&format=json`;

  const resp = await fetch(apiUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-GB,en;q=0.9',
      'X-Requested-With': 'XMLHttpRequest',
    },
    cf: { cacheEverything: true, cacheTtl: 300 },
  });

  if (!resp.ok) throw new Error(`Toolstation HTTP ${resp.status}`);

  const contentType = resp.headers.get('content-type') || '';

  if (contentType.includes('application/json')) {
    const data = await resp.json();
    const products = data.products || data.results || data.items || [];
    const first = Array.isArray(products) ? products[0] : null;
    if (first) {
      return {
        price: parseFloat(first.price || first.salePrice || first.currentPrice),
        name: first.name || first.title,
        sku: first.productCode || first.sku || first.id,
        url: `https://www.toolstation.com${first.url || '/search?q=' + encoded}`,
        inStock: first.available !== false && first.inStock !== false,
        checkedAt: new Date().toISOString(),
      };
    }
  }

  // Fallback: parse HTML response
  const html = await resp.text();
  return parseToolstationHTML(html, query);
}

function parseToolstationHTML(html, query) {
  // JSON-LD
  const jsonLdMatch = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g);
  if (jsonLdMatch) {
    for (const block of jsonLdMatch) {
      try {
        const inner = block.replace(/<script[^>]*>/, '').replace(/<\/script>/, '');
        const data = JSON.parse(inner);
        if (data['@type'] === 'ItemList' && data.itemListElement?.length) {
          const product = data.itemListElement[0].item || data.itemListElement[0];
          const offer = product.offers;
          if (offer?.price) {
            return {
              price: parseFloat(offer.price),
              name: product.name,
              sku: product.sku,
              url: product.url || `https://www.toolstation.com/search?q=${encodeURIComponent(query)}`,
              inStock: offer.availability !== 'OutOfStock',
              checkedAt: new Date().toISOString(),
            };
          }
        }
      } catch (_) {}
    }
  }

  // Price regex fallback
  const priceMatch = html.match(/class="[^"]*price[^"]*"[^>]*>\s*£([\d.]+)/i);
  if (priceMatch) {
    return {
      price: parseFloat(priceMatch[1]),
      name: query,
      sku: null,
      url: `https://www.toolstation.com/search?q=${encodeURIComponent(query)}`,
      inStock: null,
      checkedAt: new Date().toISOString(),
    };
  }

  throw new Error('Could not parse Toolstation response');
}

// ─── CEF (CITY ELECTRICAL FACTORS) ───────────────────────────────────────────
// CEF uses a Solr-based search that returns JSON

async function fetchCEF(query) {
  const encoded = encodeURIComponent(query);

  // CEF's internal product search endpoint
  const apiUrl = `https://www.cef.co.uk/search?q=${encoded}&format=json`;

  const resp = await fetch(apiUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Accept': 'application/json, */*',
      'Accept-Language': 'en-GB,en;q=0.9',
      'X-Requested-With': 'XMLHttpRequest',
    },
    cf: { cacheEverything: true, cacheTtl: 300 },
  });

  if (!resp.ok) throw new Error(`CEF HTTP ${resp.status}`);

  const contentType = resp.headers.get('content-type') || '';

  if (contentType.includes('json')) {
    try {
      const data = await resp.json();
      const products = data.products || data.results || data.data?.products || [];
      const first = Array.isArray(products) ? products[0] : null;
      if (first) {
        const price = first.price || first.unitPrice || first.tradePrice || first.salePrice;
        return {
          price: price ? parseFloat(price) : null,
          name: first.name || first.description,
          sku: first.productCode || first.sku || first.code,
          url: first.url ? `https://www.cef.co.uk${first.url}` : `https://www.cef.co.uk/search?q=${encoded}`,
          inStock: first.inStock !== false,
          checkedAt: new Date().toISOString(),
        };
      }
    } catch (_) {}
  }

  // HTML fallback
  const html = await resp.text();
  return parseCEFHTML(html, query);
}

function parseCEFHTML(html, query) {
  // JSON-LD
  const jsonLdMatch = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g);
  if (jsonLdMatch) {
    for (const block of jsonLdMatch) {
      try {
        const inner = block.replace(/<script[^>]*>/, '').replace(/<\/script>/, '');
        const data = JSON.parse(inner);
        const product = Array.isArray(data) ? data.find(d => d['@type'] === 'Product') : (data['@type'] === 'Product' ? data : null);
        if (product?.offers?.price) {
          return {
            price: parseFloat(product.offers.price),
            name: product.name,
            sku: product.sku,
            url: product.url || `https://www.cef.co.uk/search?q=${encodeURIComponent(query)}`,
            inStock: product.offers.availability !== 'OutOfStock',
            checkedAt: new Date().toISOString(),
          };
        }
      } catch (_) {}
    }
  }

  const priceMatch = html.match(/£([\d.]+)/);
  if (priceMatch) {
    return {
      price: parseFloat(priceMatch[1]),
      name: query,
      sku: null,
      url: `https://www.cef.co.uk/search?q=${encodeURIComponent(query)}`,
      inStock: null,
      checkedAt: new Date().toISOString(),
    };
  }

  throw new Error('Could not parse CEF response');
}

// ─── TRAVIS PERKINS ───────────────────────────────────────────────────────────
// Travis Perkins uses a GraphQL / REST API internally

async function fetchTravisPerkins(query) {
  const encoded = encodeURIComponent(query);

  // Travis Perkins search endpoint
  const searchUrl = `https://www.travisperkins.co.uk/search?q=${encoded}`;

  const resp = await fetch(searchUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-GB,en;q=0.9',
    },
    cf: { cacheEverything: true, cacheTtl: 300 },
  });

  if (!resp.ok) throw new Error(`Travis Perkins HTTP ${resp.status}`);

  const html = await resp.text();

  // Travis Perkins embeds Next.js __NEXT_DATA__ JSON
  const nextDataMatch = html.match(/<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/);
  if (nextDataMatch) {
    try {
      const nextData = JSON.parse(nextDataMatch[1]);
      // Navigate to products in the page props
      const pageProps = nextData?.props?.pageProps;
      const searchResults = pageProps?.searchResults || pageProps?.products || pageProps?.initialData?.products;
      const products = searchResults?.products || searchResults?.items || searchResults || [];
      const first = Array.isArray(products) ? products[0] : null;
      if (first) {
        const price = first.price?.value || first.sellPrice || first.currentPrice || first.price;
        return {
          price: price ? parseFloat(price) : null,
          name: first.name || first.title,
          sku: first.code || first.sku || first.productCode,
          url: first.url ? `https://www.travisperkins.co.uk${first.url}` : `https://www.travisperkins.co.uk/search?q=${encoded}`,
          inStock: first.inStock !== false && first.available !== false,
          checkedAt: new Date().toISOString(),
        };
      }
    } catch (_) {}
  }

  // JSON-LD fallback
  const jsonLdMatch = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g);
  if (jsonLdMatch) {
    for (const block of jsonLdMatch) {
      try {
        const inner = block.replace(/<script[^>]*>/, '').replace(/<\/script>/, '');
        const data = JSON.parse(inner);
        const items = Array.isArray(data) ? data : [data];
        for (const item of items) {
          if (item['@type'] === 'Product' || (item['@type'] === 'ItemList' && item.itemListElement?.length)) {
            const product = item['@type'] === 'ItemList' ? item.itemListElement[0]?.item : item;
            const offer = product?.offers;
            if (offer?.price) {
              return {
                price: parseFloat(offer.price),
                name: product.name,
                sku: product.sku,
                url: product.url || `https://www.travisperkins.co.uk/search?q=${encoded}`,
                inStock: offer.availability !== 'OutOfStock',
                checkedAt: new Date().toISOString(),
              };
            }
          }
        }
      } catch (_) {}
    }
  }

  // Price regex fallback
  const priceMatch = html.match(/["']price["']\s*:\s*["']?([\d.]+)["']?/);
  if (priceMatch) {
    return {
      price: parseFloat(priceMatch[1]),
      name: query,
      sku: null,
      url: `https://www.travisperkins.co.uk/search?q=${encodeURIComponent(query)}`,
      inStock: null,
      checkedAt: new Date().toISOString(),
    };
  }

  throw new Error('Could not parse Travis Perkins response');
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: CORS_HEADERS,
  });
}
