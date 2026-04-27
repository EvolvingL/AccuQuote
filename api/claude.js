/**
 * AccuQuote — Claude API proxy (Vercel Serverless Function)
 *
 * Keeps the Anthropic API key server-side. The browser never sees it.
 * Deploy to Vercel — set ANTHROPIC_API_KEY in environment variables.
 *
 * POST /api/claude
 * Body: { system, userPrompt, maxTokens? }
 * Returns: { content: "..." } or { error: "..." }
 */

export default async function handler(req, res) {
  // CORS — allow the AccuQuote web app origin in production
  const allowedOrigins = [
    'https://accuquote.netlify.app',
    'http://localhost:3000',
    'http://localhost:5000',
    // Add your Netlify subdomain here once deployed
  ];
  const origin = req.headers.origin || '';
  if (allowedOrigins.includes(origin) || origin.endsWith('.netlify.app') || origin.endsWith('.vercel.app')) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: 'ANTHROPIC_API_KEY not configured on server' });
    return;
  }

  const { system, userPrompt, maxTokens = 2000 } = req.body || {};
  if (!userPrompt) {
    res.status(400).json({ error: 'Missing userPrompt' });
    return;
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
      res.status(response.status).json({ error: `Anthropic API error: ${err}` });
      return;
    }

    const data = await response.json();
    const content = data.content?.[0]?.text || '';
    res.status(200).json({ content });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}
