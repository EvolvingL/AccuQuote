/**
 * AccuQuote Service Worker
 * - Caches app shell for offline use
 * - Network-first for API calls, cache-first for static assets
 */

const CACHE_VERSION = 'accuquote-v1';
const STATIC_CACHE = `${CACHE_VERSION}-static`;
const API_CACHE = `${CACHE_VERSION}-api`;

const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  'https://cdn.tailwindcss.com',
  'https://unpkg.com/react@18/umd/react.production.min.js',
  'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone/babel.min.js',
  'https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@400;700;900&family=Inter:wght@300;400;500;600&display=swap',
];

// Install: cache static shell
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then(cache => {
      // Cache what we can — external CDN resources may fail, that's OK
      return Promise.allSettled(STATIC_ASSETS.map(url => cache.add(url).catch(() => {})));
    }).then(() => self.skipWaiting())
  );
});

// Activate: remove old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key.startsWith('accuquote-') && key !== STATIC_CACHE && key !== API_CACHE)
          .map(key => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

// Fetch strategy
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests and browser extensions
  if (request.method !== 'GET') return;
  if (!url.protocol.startsWith('http')) return;

  // API calls — network first, no caching
  if (url.pathname.startsWith('/api/') || url.hostname.includes('anthropic.com') || url.hostname.includes('workers.dev')) {
    event.respondWith(fetch(request).catch(() => new Response(JSON.stringify({ error: 'Offline' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' }
    })));
    return;
  }

  // App shell (index.html) — cache first, fallback to network
  if (url.pathname === '/' || url.pathname === '/index.html' || url.pathname.endsWith('.html')) {
    event.respondWith(
      caches.match('/index.html').then(cached => cached || fetch(request))
    );
    return;
  }

  // Static assets — stale-while-revalidate
  event.respondWith(
    caches.open(STATIC_CACHE).then(async cache => {
      const cached = await cache.match(request);
      const networkFetch = fetch(request).then(response => {
        if (response.ok) cache.put(request, response.clone());
        return response;
      }).catch(() => cached);
      return cached || networkFetch;
    })
  );
});

// Background sync for offline quote saves (future use)
self.addEventListener('sync', event => {
  if (event.tag === 'sync-quotes') {
    event.waitUntil(syncOfflineQuotes());
  }
});

async function syncOfflineQuotes() {
  // Placeholder — when backend auth is added, sync any offline-created quotes
  console.log('[SW] Syncing offline quotes');
}
