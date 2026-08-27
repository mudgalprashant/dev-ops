---
title: Deployment — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Deployment

## One artefact, one origin

`wrangler deploy` publishes **the Worker and the client together** as a single version. The
client is not a separate site: `apps/web/dist` is uploaded as the Worker's static assets, so
`https://<worker>.workers.dev/` serves `index.html` and `/api/*` reaches the same code.

That is the whole reason there is no CORS configuration, no second host to keep awake, and
no way for the client and the server to be at different versions on the origin.

```
push to cellbreak-dev  ──▶  CI: install, test, typecheck, build          (no deploy)
merge to cellbreak     ──▶  CI: the same, then `wrangler deploy`         (deploy)
```

## The order that matters

```
pnpm install
pnpm test
pnpm typecheck
pnpm --filter @cellbreak/web build       ← BEFORE the next line, always
pnpm --filter @cellbreak/server deploy
```

⚠️ **`wrangler deploy` uploads whatever is already in `apps/web/dist`.** It does not build
the client, and it does not warn you that the directory is stale. Deploying without
building ships the previous client against the new Worker — which is exactly the
old-client/new-protocol failure in [observability.md](observability.md) §4, caused on
purpose by accident. `ci/deploy.yml` encodes the order; match it when deploying by hand.

## What a deploy does to games in flight

A new Worker version restarts Durable Objects. Rooms reload from storage, so:

| | What players see |
| --- | --- |
| In a lobby | a brief reconnect, then the lobby again. Nothing lost |
| Mid-game | reconnect, board resumes at the last settled position |
| **Mid-cascade** | the board **jumps** to the settled position — the animation is client-side and does not survive |
| Already-loaded tabs | keep the **old** client until they reload |

None of it loses a game, and the last row is the one that causes support questions. Deploy
between games when you can.

## Environments

**There is one.** No staging, and that is deliberate: a staging environment for a stateless
game with no database and no data migrations would test nothing that `wrangler dev` does not
test locally, while doubling the deploy surface.

The two local modes and what each is for are in [env-matrix.md](env-matrix.md).

## First deploy

Follow [HUMAN-SETUP-CHECKLIST.md](HUMAN-SETUP-CHECKLIST.md). The first `wrangler deploy`
creates the Durable Object namespace from the `migrations` block in `wrangler.jsonc`.

⚠️ **The migration tags use `new_sqlite_classes`, and that is load-bearing.** SQLite-backed
Durable Objects are the kind available on the free plan; the older key-value backend is not.

There are two tags now: `v1` created `RoomDO`, and `v2` adds `StatsDO` for the visitor
count. **Never edit an applied tag** — `v1` is already live, so a new class arrives as a
new tag. Migrations apply on deploy; there is nothing separate to run.

## Rollback

[runbook.md](runbook.md#roll-back), including the trap that `wrangler rollback` may not
take the client bundle back with it.
