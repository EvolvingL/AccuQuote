// Minimal RFC 4180-ish delimited-text parser with double-quote escaping.
// Awin lets each publisher pick their feed's delimiter per-datafeed —
// confirmed live: Travis Perkins' feed is tab-delimited (\t), not comma,
// despite field names like "aw_deep_link"/"search_price" matching the Awin
// spec exactly. This general-purpose export defaults to comma (true CSV);
// refresh.js's real-feed ingestion path passes '\t' explicitly per supplier
// via its own DELIMITERS map — see refresh.js.
export function parseCsv(text, delimiter = ',') {
  const rows = parseCsvLines(text, delimiter);
  const header = rows.shift();
  if (!header) return [];
  return rowsToObjects(header, rows);
}

// Row-only parser (no header handling) — shared by parseCsv and the
// streaming chunk reader below, which supplies its own header once and
// reuses it across many chunks instead of expecting it in every slice.
export function parseCsvLines(text, delimiter = ',') {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    const next = text[i + 1];

    if (inQuotes) {
      if (c === '"' && next === '"') { field += '"'; i++; }
      else if (c === '"') { inQuotes = false; }
      else { field += c; }
    } else {
      if (c === '"') inQuotes = true;
      else if (c === delimiter) { row.push(field); field = ''; }
      else if (c === '\r') { /* skip, \n handles the line break */ }
      else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
      else field += c;
    }
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows;
}

export function rowsToObjects(header, rows) {
  return rows
    .filter(r => r.length === header.length && r.some(v => v !== ''))
    .map(r => Object.fromEntries(header.map((h, idx) => [h, r[idx]])));
}
