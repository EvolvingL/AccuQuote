// MARK: - Structured logger
//
// Zero-dependency JSON-line logger. Render's log viewer (and most log
// aggregators) parse one-JSON-object-per-line natively — this gives us
// timestamp, level, message, and arbitrary structured fields (requestId,
// route, err.stack, etc.) without adding a package dependency for something
// this small.
//
// Usage: log.info('message', { key: 'value' }) / log.error('message', { err })
// Passing an Error under any field key auto-expands to { message, stack, name }
// so stack traces actually survive JSON serialization (Error.stack is
// non-enumerable and JSON.stringify(error) silently drops it otherwise —
// the bug that made the crash which caused this file to be written invisible
// in the first place).

function serializeError(err) {
  if (!(err instanceof Error)) return err;
  return { name: err.name, message: err.message, stack: err.stack };
}

function serializeFields(fields) {
  if (!fields) return undefined;
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    out[key] = value instanceof Error ? serializeError(value) : value;
  }
  return out;
}

function write(level, message, fields) {
  const line = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...serializeFields(fields),
  };
  const out = level === 'error' || level === 'fatal' ? console.error : console.log;
  out(JSON.stringify(line));
}

export const log = {
  info:  (message, fields) => write('info', message, fields),
  warn:  (message, fields) => write('warn', message, fields),
  error: (message, fields) => write('error', message, fields),
  fatal: (message, fields) => write('fatal', message, fields),
};

// ── Process-level crash visibility ──────────────────────────────────────────
//
// Without these, an unhandled exception or rejected promise anywhere in the
// app crashes the whole Node process with ZERO log output — Render just shows
// a bare restart ("Detected service running on port ..."), which is exactly
// what happened and is why this file exists. These two handlers guarantee the
// actual error is written to the log before the process exits, so the next
// crash is diagnosable instead of a silent mystery.
//
// Node's own guidance (and ours): log and exit, don't try to keep running —
// the process is in an unknown state after an uncaught exception, and
// swallowing it to "stay up" risks corrupting in-flight requests silently.
// Render will restart the process immediately, so a clean exit + restart is
// safer than limping on.
export function installCrashHandlers() {
  process.on('uncaughtException', (err) => {
    log.fatal('uncaughtException — process will exit', { err });
    process.exit(1);
  });

  process.on('unhandledRejection', (reason) => {
    log.fatal('unhandledRejection — process will exit', {
      err: reason instanceof Error ? reason : new Error(String(reason)),
    });
    process.exit(1);
  });
}
