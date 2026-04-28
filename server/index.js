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

// ── Serve static web app ─────────────────────────────────────────────────────
// Serves index.html, sw.js, manifest.json, icons/, etc. from project root
const ROOT = join(__dirname, '..');
app.use(express.static(ROOT, {
  maxAge: '1y',
  setHeaders: (res, filePath) => {
    // Never cache index.html or sw.js
    if (filePath.endsWith('index.html') || filePath.endsWith('sw.js')) {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    }
  },
}));

// SPA fallback — all unmatched routes serve index.html
app.get('*', (req, res) => {
  res.sendFile(join(ROOT, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`AccuQuote server running on port ${PORT}`);
});
