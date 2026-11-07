// Used by the Dockerfile HEALTHCHECK: the runtime image has no shell or curl.
const port = process.env.PORT ?? 8080;

try {
  const res = await fetch(`http://127.0.0.1:${port}/healthz`, { signal: AbortSignal.timeout(2000) });
  process.exit(res.ok ? 0 : 1);
} catch {
  process.exit(1);
}
