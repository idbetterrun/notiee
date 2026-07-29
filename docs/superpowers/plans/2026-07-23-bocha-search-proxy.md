# Bocha Search Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the free-backend `POST /ai/search` proxy so Agent web search can use the server-side Bocha API key.

**Architecture:** Keep the existing single-file Express service. First expose its configured Express `app` only when required as a module, allowing a Node native integration test to run the app on an ephemeral port. Then add a narrow Bocha adapter and route that apply existing JWT authentication, enforce the existing Pro Agent boundary, validate the established client contract, and map Bocha data to the client response shape.

**Tech Stack:** Node.js 22 built-in `node:test`, `node:assert`, Express 5, global `fetch`.

## Global Constraints

- Scope is free-target backend only: `notiee-ping-stream/`; do not modify Notiee+ or iOS client files.
- Use environment variable `BOCHA_API_KEY`; never return or log its value.
- Keep Bocha endpoint fixed at `https://api.bochaai.com/v1/web-search` and preserve the existing upstream timeout/disconnect-abort pattern.
- `/ai/search` must require a valid JWT and `user.tier === 'pro'`; it does not consume processing quota or persist data.
- Do not commit or create a branch unless the user explicitly asks.

---

### Task 1: Add a Testable Server Entry Point

**Files:**
- Create: `notiee-ping-stream/test/index.test.js`
- Modify: `notiee-ping-stream/index.js:703-704`
- Modify: `notiee-ping-stream/package.json:6-9`

**Interfaces:**
- Produces: `module.exports = { app, memoryStore, signJwt }` when `index.js` is required.
- Produces: `npm test` runs `node --test` in `notiee-ping-stream`.
- The SCF production path still calls `app.listen(process.env.PORT || 9000)` when `node index.js` is executed directly.

- [x] **Step 1: Write the failing export-seam test**

Create `notiee-ping-stream/test/index.test.js`:

```js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

test('index exports the Express app for integration tests', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');
  assert.match(source, /module\.exports\s*=\s*\{\s*app,\s*memoryStore,\s*signJwt\s*\}/);
});
```

- [x] **Step 2: Run the test to verify it fails for the missing test seam**

Run: `npm test --prefix notiee-ping-stream`

Expected: FAIL because `index.js` does not yet export the required objects.

- [x] **Step 3: Add the minimal export seam and Node test command**

Replace the current unconditional `app.listen` tail with:

```js
const port = process.env.PORT || 9000;
if (require.main === module) {
  app.listen(port, () => console.log(`listening on ${port}`));
}

module.exports = { app, memoryStore, signJwt };
```

Change the `test` script in `notiee-ping-stream/package.json` to:

```json
"test": "node --test"
```

- [x] **Step 4: Run the test to verify it passes**

Run: `npm test --prefix notiee-ping-stream`

Expected: PASS with one passing test and no server listening as a side effect.

### Task 2: Add the Authenticated Bocha Search Proxy

**Files:**
- Modify: `notiee-ping-stream/index.js:390-561`
- Modify: `notiee-ping-stream/test/index.test.js`

**Interfaces:**
- Consumes: exported `app`, `memoryStore`, and `signJwt` from Task 1.
- Produces: `POST /ai/search`, accepting `{ query, count?, freshness? }` and returning `{ results: [{ name, url, summary, snippet, siteName, datePublished }] }`.

- [x] **Step 1: Write failing integration tests for the route**

Append helpers that run `app` on an ephemeral HTTP port and issue JSON requests with `http.request`. Add serial tests that:

```js
test('search rejects a free user before contacting Bocha', { concurrency: false }, async () => {
  const response = await request('/ai/search', freeToken, { query: 'weather' });
  assert.equal(response.status, 403);
  assert.equal(response.body.error.code, 'UPGRADE_REQUIRED');
});

test('search returns a configuration error without BOCHA_API_KEY', { concurrency: false }, async () => {
  delete process.env.BOCHA_API_KEY;
  const response = await request('/ai/search', proToken, { query: 'weather' });
  assert.equal(response.status, 503);
  assert.equal(response.body.error.code, 'CONFIGURATION_ERROR');
});
```

Add one success test that stubs `global.fetch`, asserts the Bocha request carries `Authorization: Bearer test-bocha-key` and `{ query: 'weather', count: 3, freshness: 'oneDay', summary: true }`, then verifies the six allowed result fields are mapped. Add one invalid-input test expecting `400 BAD_REQUEST` and one upstream-500 stub expecting `502 UPSTREAM_ERROR`.

- [x] **Step 2: Run the integration tests to verify they fail because `/ai/search` is absent**

Run: `npm test --prefix notiee-ping-stream`

Expected: the new route tests fail with the current 404 response while the Task 1 export-seam test remains green.

- [x] **Step 3: Implement the minimal Bocha adapter and route**

Add a `BOCHA_SEARCH_ENDPOINT` constant, a `normalizeSearchRequest(body)` validator, and `callBochaSearch({ query, count, freshness }, req)` near the existing upstream helpers. The adapter reads `process.env.BOCHA_API_KEY`, starts an `AbortController` with `CONFIG.upstreamTimeoutMs`, sets `Content-Type` and Bearer headers, posts `summary: true`, maps `data.webPages.value`, and always clears its timer/listener.

Register `app.post('/ai/search', verifyToken, async (req, res) => { ... })` before `/ai/agent`. It must validate input, load the user, reject a non-Pro user, return `503 CONFIGURATION_ERROR` when the key is absent, and return `502 UPSTREAM_ERROR` for failures without exposing the API key.

- [x] **Step 4: Run the complete backend suite to verify it passes**

Run: `npm test --prefix notiee-ping-stream`

Expected: all export-seam and `/ai/search` integration tests pass.

- [x] **Step 5: Check the exact changed surface**

Run: `git diff --check && git diff -- notiee-ping-stream/index.js notiee-ping-stream/package.json notiee-ping-stream/test/index.test.js`

Expected: no whitespace errors; only the backend implementation, its tests, and its test script changed.
