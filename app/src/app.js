import { createServer } from 'node:http';

const SERVICE = 'kettlebird-hello';

function send(res, status, contentType, body, extraHeaders = {}) {
  res.writeHead(status, {
    'content-type': contentType,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...extraHeaders,
  });
  res.end(body);
}

// The whole service: GET / says which version is running, GET /healthz is the probe.
export function createApp({ version = 'dev' } = {}) {
  return createServer((req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      send(res, 405, 'text/plain; charset=utf-8', 'method not allowed\n', { allow: 'GET, HEAD' });
      return;
    }

    const { pathname } = new URL(req.url ?? '/', 'http://localhost');

    if (pathname === '/healthz') {
      send(res, 200, 'text/plain; charset=utf-8', 'ok\n');
    } else if (pathname === '/') {
      send(res, 200, 'application/json', `${JSON.stringify({ service: SERVICE, version })}\n`);
    } else {
      send(res, 404, 'text/plain; charset=utf-8', 'not found\n');
    }
  });
}
