# Bocha Search Proxy Design

| Field | Value |
| --- | --- |
| Date | 2026-07-23 |
| Scope | Free-target backend only: `notiee-ping-stream/` |
| Status | Implemented and verified |

## Problem

The free-build `WebSearchTool` calls authenticated `POST /ai/search`, but the
checked-in Express backend has no such route. The free build therefore cannot
execute the Agent's `web_search` tool. Notiee+ already calls Bocha directly
using the user's own Keychain-stored key and must not change.

## Goal

Provide an authenticated, Pro-only backend proxy for Bocha web search. The
service key remains server-side and the response matches the free client.

## Non-Goals

- Do not change iOS client code, the Notiee+ direct-BYOK flow, or Agent tools.
- Do not charge note-processing quota, persist search data, add database tables,
  or add a separate rate limiter.
- Do not expose `BOCHA_API_KEY` in HTTP responses or logs.

## API Contract

`POST /ai/search` requires `Authorization: Bearer <Notiee backend JWT>` and a
JSON body `{ "query": string, "count": integer?, "freshness": string? }`.
`query` is a non-empty trimmed string; `count` is 1 through 10 (default 5);
`freshness` accepts `noLimit`, `oneYear`, `oneMonth`, `oneWeek`, `oneDay`, a
`YYYY-MM-DD` date, or `YYYY-MM-DD..YYYY-MM-DD` range (default `noLimit`).

The route uses `verifyToken`, loads the user through `store.getUser`, and
returns `403 UPGRADE_REQUIRED` unless `user.tier === 'pro'`. This mirrors
`/ai/agent` so a free session cannot bypass the client-side Agent lock.

The server reads `BOCHA_API_KEY`, posts to
`https://api.bochaai.com/v1/web-search`, and sends:

```json
{ "query": "example", "count": 5, "freshness": "oneDay", "summary": true }
```

It uses the existing `CONFIG.upstreamTimeoutMs` and cancels the upstream fetch
when the app client disconnects, like the existing model proxies.

The response is `{ "results": [...] }`, mapping Bocha's
`data.webPages.value` to the client-recognized fields `name`, `url`, `summary`,
`snippet`, `siteName`, and `datePublished`. Missing/malformed result arrays map
to an empty list; other Bocha fields are not relayed.

## Errors

| Situation | Status | Error code |
| --- | --- | --- |
| Missing or invalid backend JWT | 401 | `UNAUTHORIZED` |
| User is not Pro | 403 | `UPGRADE_REQUIRED` |
| Invalid request fields | 400 | `BAD_REQUEST` |
| `BOCHA_API_KEY` is absent | 503 | `CONFIGURATION_ERROR` |
| Bocha rejects or times out | 502 | `UPSTREAM_ERROR` |

Upstream errors must never include the configured key or raw authorization
header.

## Verification

Add Node built-in `node:test` coverage without new production dependencies. It
must cover invalid input, non-Pro access, absent key, normalized forwarding with
`summary: true`, response mapping, and upstream failure mapping. This is a
backend-only change, so an Xcode build is not required.
