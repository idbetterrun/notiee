const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PassThrough, Readable } = require('node:stream');
const test = require('node:test');

const { app, memoryStore, signJwt } = require('../index');

const jwtSecret = 'dev-secret-change-me';
const originalFetch = global.fetch;
const originalBochaAPIKey = process.env.BOCHA_API_KEY;
const originalDeepSeekAPIKey = process.env.DEEPSEEK_API_KEY;

test.after(() => {
  global.fetch = originalFetch;
  if (originalBochaAPIKey === undefined) {
    delete process.env.BOCHA_API_KEY;
  } else {
    process.env.BOCHA_API_KEY = originalBochaAPIKey;
  }
  if (originalDeepSeekAPIKey === undefined) {
    delete process.env.DEEPSEEK_API_KEY;
  } else {
    process.env.DEEPSEEK_API_KEY = originalDeepSeekAPIKey;
  }
});

function tokenFor(userId) {
  return signJwt({ sub: userId }, jwtSecret, 60 * 60);
}

function request(pathname, token, body) {
  const payload = JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = new Readable({
      read() {
        this.push(payload);
        this.push(null);
      },
    });
    const reqOn = req.on.bind(req);
    const reqOnce = req.once.bind(req);
    const reqEmit = req.emit.bind(req);
    const reqRead = req.read.bind(req);
    const reqResume = req.resume.bind(req);
    const reqDestroy = req.destroy.bind(req);
    const reqUnpipe = req.unpipe.bind(req);
    Object.assign(req, {
      method: 'POST',
      url: pathname,
      originalUrl: pathname,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        'content-length': String(Buffer.byteLength(payload)),
      },
      httpVersion: '1.1',
      readable: true,
      on: reqOn,
      once: reqOnce,
      emit: reqEmit,
      read: reqRead,
      resume: reqResume,
      destroy: reqDestroy,
      unpipe: reqUnpipe,
    });

    const res = new PassThrough();
    const resOn = res.on.bind(res);
    const resOnce = res.once.bind(res);
    const resEmit = res.emit.bind(res);
    const headers = new Map();
    const chunks = [];
    Object.assign(res, {
      statusCode: 200,
      on: resOn,
      once: resOnce,
      emit: resEmit,
      setHeader(name, value) { headers.set(String(name).toLowerCase(), value); },
      getHeader(name) { return headers.get(String(name).toLowerCase()); },
      getHeaderNames() { return [...headers.keys()]; },
      removeHeader(name) { headers.delete(String(name).toLowerCase()); },
      writeHead(statusCode, responseHeaders) {
        this.statusCode = statusCode;
        for (const [name, value] of Object.entries(responseHeaders || {})) this.setHeader(name, value);
        return this;
      },
      write(chunk) {
        if (chunk) chunks.push(Buffer.from(chunk));
        return true;
      },
      end(chunk) {
        if (chunk) chunks.push(Buffer.from(chunk));
        const raw = Buffer.concat(chunks).toString('utf8');
        let parsed;
        try {
          parsed = JSON.parse(raw);
        } catch {
          parsed = { raw };
        }
        resolve({ status: this.statusCode, body: parsed });
        this.emit('finish');
      },
    });

    app.handle(req, res);
    req.once('error', reject);
  });
}

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: `status-${status}`,
    json: async () => body,
  };
}

const memoryCandidateID = '11111111-1111-4111-8111-111111111111';

function memoryRequestBody(overrides = {}) {
  return {
    model: 'deepseek-v4-flash',
    userMessage: '我喜欢喝拿铁',
    confirmedToolResults: [],
    candidates: [{
      id: memoryCandidateID,
      text: '我以前喜欢喝美式咖啡',
      category: 'preference',
      topicKey: 'preference.coffee',
    }],
    ...overrides,
  };
}

function memoryProposal(overrides = {}) {
  return {
    text: '我喜欢喝拿铁',
    category: 'preference',
    durability: 'stable',
    topicKey: 'preference.coffee',
    entities: [],
    keywords: ['拿铁'],
    eventAt: null,
    expiresAt: null,
    evidenceQuote: '我喜欢喝拿铁',
    evidenceSource: 'user',
    relatedMemoryID: memoryCandidateID,
    relationship: 'supersede',
    ...overrides,
  };
}

function upstreamMemoryResponse(proposals) {
  return jsonResponse(200, {
    choices: [{ message: { content: JSON.stringify({ proposals }) } }],
    usage: { total_tokens: 42 },
  });
}

test('index exports the Express app for integration tests', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');
  assert.match(source, /module\.exports\s*=\s*\{\s*app,\s*memoryStore,\s*signJwt\s*\}/);
});

test('memory extraction requires authentication', { concurrency: false }, async () => {
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return upstreamMemoryResponse([]); };

  const response = await request('/ai/memory/extract', 'invalid-token', memoryRequestBody());

  assert.equal(response.status, 401);
  assert.equal(fetchCalled, false);
});

test('memory extraction enforces request limits before upstream', { concurrency: false }, async () => {
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return upstreamMemoryResponse([]); };

  const response = await request('/ai/memory/extract', tokenFor('memory-too-long'), memoryRequestBody({
    userMessage: 'a'.repeat(4001),
  }));

  assert.equal(response.status, 400);
  assert.equal(response.body.error.code, 'BAD_REQUEST');
  assert.equal(fetchCalled, false);
});

test('memory extraction rejects unknown request and candidate fields', { concurrency: false }, async () => {
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return upstreamMemoryResponse([]); };

  const unknownRoot = await request(
    '/ai/memory/extract',
    tokenFor('memory-unknown-root'),
    memoryRequestBody({ unexpected: true }),
  );
  assert.equal(unknownRoot.status, 400);
  assert.equal(unknownRoot.body.error.code, 'BAD_REQUEST');

  const body = memoryRequestBody();
  body.candidates[0].unexpected = true;
  const unknownCandidate = await request(
    '/ai/memory/extract',
    tokenFor('memory-unknown-candidate'),
    body,
  );
  assert.equal(unknownCandidate.status, 400);
  assert.equal(unknownCandidate.body.error.code, 'BAD_REQUEST');
  assert.equal(fetchCalled, false);
});

test('memory extraction rejects a model outside the text whitelist', { concurrency: false }, async () => {
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return upstreamMemoryResponse([]); };

  const response = await request('/ai/memory/extract', tokenFor('memory-bad-model'), memoryRequestBody({
    model: 'does-not-exist',
  }));

  assert.equal(response.status, 400);
  assert.equal(response.body.error.code, 'BAD_MODEL');
  assert.equal(fetchCalled, false);
});

test('memory extraction rejects malformed upstream JSON', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
  global.fetch = async () => jsonResponse(200, {
    choices: [{ message: { content: 'not-json' } }],
    usage: { total_tokens: 4 },
  });

  const response = await request('/ai/memory/extract', tokenFor('memory-malformed-json'), memoryRequestBody());

  assert.equal(response.status, 502);
  assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
});

test('memory extraction rejects unknown and missing upstream fields', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';

  global.fetch = async () => jsonResponse(200, {
    choices: [{ message: { content: JSON.stringify({ proposals: [], unexpected: true }) } }],
    usage: { total_tokens: 4 },
  });
  const unknownRoot = await request(
    '/ai/memory/extract',
    tokenFor('memory-upstream-unknown-root'),
    memoryRequestBody(),
  );
  assert.equal(unknownRoot.status, 502);
  assert.equal(unknownRoot.body.error.code, 'UPSTREAM_ERROR');

  const unknownProposal = memoryProposal({ unexpected: true });
  global.fetch = async () => upstreamMemoryResponse([unknownProposal]);
  const unknownProposalResponse = await request(
    '/ai/memory/extract',
    tokenFor('memory-upstream-unknown-proposal'),
    memoryRequestBody(),
  );
  assert.equal(unknownProposalResponse.status, 502);
  assert.equal(unknownProposalResponse.body.error.code, 'UPSTREAM_ERROR');

  const missingNullableField = memoryProposal();
  delete missingNullableField.expiresAt;
  global.fetch = async () => upstreamMemoryResponse([missingNullableField]);
  const missingFieldResponse = await request(
    '/ai/memory/extract',
    tokenFor('memory-upstream-missing-field'),
    memoryRequestBody(),
  );
  assert.equal(missingFieldResponse.status, 502);
  assert.equal(missingFieldResponse.body.error.code, 'UPSTREAM_ERROR');
});

test('memory extraction rejects inconsistent relationship and related id', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
  global.fetch = async () => upstreamMemoryResponse([
    memoryProposal({ relationship: 'none' }),
  ]);

  const response = await request(
    '/ai/memory/extract',
    tokenFor('memory-inconsistent-relationship'),
    memoryRequestBody(),
  );

  assert.equal(response.status, 502);
  assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
});

test('memory extraction rejects an unrelated memory id', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
  global.fetch = async () => upstreamMemoryResponse([
    memoryProposal({ relatedMemoryID: '22222222-2222-4222-8222-222222222222' }),
  ]);

  const response = await request('/ai/memory/extract', tokenFor('memory-bad-related-id'), memoryRequestBody());

  assert.equal(response.status, 502);
  assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
});

test('memory extraction rejects forbidden secrets in proposals', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
  global.fetch = async () => upstreamMemoryResponse([
    memoryProposal({
      text: 'API Key: sk-1234567890abcdefgh',
      evidenceQuote: '我喜欢喝拿铁',
      relatedMemoryID: null,
      relationship: 'none',
    }),
  ]);

  const response = await request('/ai/memory/extract', tokenFor('memory-secret'), memoryRequestBody());

  assert.equal(response.status, 502);
  assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
});

for (const [name, secret] of [
  ['payment card', '请记住银行卡 4111 1111 1111 1111'],
  ['generic token', 'token: abcdefghijklmnop'],
  ['JWT', 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature1234'],
  ['GitHub token', 'ghp_abcdefghijklmnopqrstuvwxyz123456'],
  ['private key', '-----BEGIN RSA PRIVATE KEY-----'],
  ['Chinese password', '密码是 hunter2'],
  ['Chinese token', '令牌是 abc'],
]) {
  test(`memory extraction rejects ${name}`, { concurrency: false }, async () => {
    process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
    global.fetch = async () => upstreamMemoryResponse([
      memoryProposal({
        text: secret,
        evidenceQuote: '我喜欢喝拿铁',
        relatedMemoryID: null,
        relationship: 'none',
      }),
    ]);

    const response = await request('/ai/memory/extract', tokenFor(`memory-secret-${name}`), memoryRequestBody());

    assert.equal(response.status, 502);
    assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
  });
}

test('memory extraction forwards bounded context and returns a strict proposal envelope', { concurrency: false }, async () => {
  process.env.DEEPSEEK_API_KEY = 'test-deepseek-key';
  let captured;
  const proposals = [memoryProposal()];
  global.fetch = async (url, options) => {
    captured = { url, options };
    return upstreamMemoryResponse(proposals);
  };

  const response = await request('/ai/memory/extract', tokenFor('memory-success'), memoryRequestBody());

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, { proposals });
  assert.equal(captured.options.headers.Authorization, 'Bearer test-deepseek-key');
  const upstreamBody = JSON.parse(captured.options.body);
  assert.equal(upstreamBody.max_tokens, 1600);
  assert.match(upstreamBody.messages[0].content, /You extract durable user facts for Notti/);
  const payload = JSON.parse(upstreamBody.messages[1].content);
  assert.equal(payload.USER_MESSAGE, '我喜欢喝拿铁');
  assert.equal(payload.RELATED_LOCAL_CANDIDATES.length, 1);
  assert.equal(payload.RELATED_LOCAL_CANDIDATES[0].id, memoryCandidateID);
});

test('search rejects a free user before contacting Bocha', { concurrency: false }, async () => {
  let fetchCalled = false;
  global.fetch = async () => { fetchCalled = true; return jsonResponse(200, {}); };

  const response = await request('/ai/search', tokenFor('free-search-user'), { query: 'weather' });

  assert.equal(response.status, 403);
  assert.equal(response.body.error.code, 'UPGRADE_REQUIRED');
  assert.equal(fetchCalled, false);
});

test('search returns a configuration error without BOCHA_API_KEY', { concurrency: false }, async () => {
  delete process.env.BOCHA_API_KEY;
  await memoryStore.setTier('pro-without-key', 'pro');

  const response = await request('/ai/search', tokenFor('pro-without-key'), { query: 'weather' });

  assert.equal(response.status, 503);
  assert.equal(response.body.error.code, 'CONFIGURATION_ERROR');
});

test('search rejects an invalid query', { concurrency: false }, async () => {
  await memoryStore.setTier('pro-invalid-query', 'pro');

  const response = await request('/ai/search', tokenFor('pro-invalid-query'), { query: '   ' });

  assert.equal(response.status, 400);
  assert.equal(response.body.error.code, 'BAD_REQUEST');
});

test('search forwards Bocha parameters and maps allowed result fields', { concurrency: false }, async () => {
  process.env.BOCHA_API_KEY = 'test-bocha-key';
  await memoryStore.setTier('pro-success', 'pro');
  let captured;
  global.fetch = async (url, options) => {
    captured = { url, options };
    return jsonResponse(200, {
      data: {
        webPages: {
          value: [{
            name: 'Weather report',
            url: 'https://example.com/weather',
            summary: 'Sunny',
            snippet: 'Fallback',
            siteName: 'Example',
            datePublished: '2026-07-23',
            trackingId: 'must-not-leak',
          }],
        },
      },
    });
  };

  const response = await request('/ai/search', tokenFor('pro-success'), {
    query: '  weather  ', count: 3, freshness: 'oneDay',
  });

  assert.equal(response.status, 200);
  assert.equal(captured.url, 'https://api.bochaai.com/v1/web-search');
  assert.equal(captured.options.headers.Authorization, 'Bearer test-bocha-key');
  assert.deepEqual(JSON.parse(captured.options.body), {
    query: 'weather', count: 3, freshness: 'oneDay', summary: true,
  });
  assert.deepEqual(response.body, {
    results: [{
      name: 'Weather report',
      url: 'https://example.com/weather',
      summary: 'Sunny',
      snippet: 'Fallback',
      siteName: 'Example',
      datePublished: '2026-07-23',
    }],
  });
});

test('search maps a Bocha failure to an upstream error', { concurrency: false }, async () => {
  process.env.BOCHA_API_KEY = 'test-bocha-key';
  await memoryStore.setTier('pro-upstream-failure', 'pro');
  global.fetch = async () => jsonResponse(500, { error: { message: 'Bocha unavailable' } });

  const response = await request('/ai/search', tokenFor('pro-upstream-failure'), { query: 'weather' });

  assert.equal(response.status, 502);
  assert.equal(response.body.error.code, 'UPSTREAM_ERROR');
});
