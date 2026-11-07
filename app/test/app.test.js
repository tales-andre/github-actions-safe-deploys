import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';

describe('kettlebird-hello', () => {
  let server;
  let base;

  before(async () => {
    server = createApp({ version: 'v1.2.3' });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => server.close(resolve)));

  it('answers the health probe', async () => {
    const res = await fetch(`${base}/healthz`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), 'ok\n');
  });

  it('reports the version it was built with', async () => {
    const res = await fetch(`${base}/`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /^application\/json/);
    assert.deepEqual(await res.json(), { service: 'kettlebird-hello', version: 'v1.2.3' });
  });

  it('ignores the query string when routing', async () => {
    const res = await fetch(`${base}/healthz?probe=readiness`);
    assert.equal(res.status, 200);
  });

  it('returns 404 for unknown paths', async () => {
    const res = await fetch(`${base}/admin`);
    assert.equal(res.status, 404);
  });

  it('only accepts GET and HEAD', async () => {
    const head = await fetch(`${base}/healthz`, { method: 'HEAD' });
    assert.equal(head.status, 200);

    const post = await fetch(`${base}/`, { method: 'POST', body: 'x' });
    assert.equal(post.status, 405);
    assert.equal(post.headers.get('allow'), 'GET, HEAD');
  });

  it('sends no-store and nosniff on every response', async () => {
    const res = await fetch(`${base}/`);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  });

  it('defaults the version to "dev"', async () => {
    const dev = createApp();
    await new Promise((resolve) => dev.listen(0, '127.0.0.1', resolve));
    try {
      const res = await fetch(`http://127.0.0.1:${dev.address().port}/`);
      assert.equal((await res.json()).version, 'dev');
    } finally {
      await new Promise((resolve) => dev.close(resolve));
    }
  });
});
