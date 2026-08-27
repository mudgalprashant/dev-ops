---
title: Observability — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Observability

**A game does not page you.** Nothing here writes an error to a dashboard when it goes
wrong — it just stops being fun, and the player closes the tab. Every failure below is
silent in exactly that way, and this file exists so nobody has to rediscover them.

## What we actually have

| Signal | Where | Good for |
| --- | --- | --- |
| Workers Logs | Cloudflare dashboard → the Worker → Logs (`observability.enabled` in `wrangler.jsonc`) | exceptions, request volume, per-room request counts |
| `wrangler tail` | a terminal | watching one room live while reproducing something |
| Durable Object metrics | dashboard → Durable Objects | object count and storage — **the abuse signal** |
| The protocol itself | `n`, the move number on every move | the only desync detector that exists |

There is no Sentry, no uptime monitor and no alerting. An uptime monitor's job in the
baseline stack is keeping a free service awake; nothing here sleeps, so a monitor would
only tell us Cloudflare is up.

## The seven silent failures

### 1. Client and server disagree about the rules

**The one that matters most.** Both sides run `packages/engine`. If a deploy changes the
engine while games are in flight, connected clients keep the old bundle and the Worker has
the new one — so the same move produces two different boards.

- **Symptom:** a player says "it did something different on my screen". Nothing is logged.
- **What catches it:** the move number `n`. A client whose board is at a different move
  gets `OUT_OF_SYNC` and a fresh snapshot. This *repairs* the symptom but does not report
  the cause.
- ⚠️ **A rising rate of `OUT_OF_SYNC` right after a deploy is the tell.** During normal play
  it should be near zero.

### 2. A room that never evicts

Deletion depends on the alarm chain: `scheduleAlarm` → `alarm()` → `scheduleAlarm`. If
`alarm()` throws before it re-arms, the chain stops and the room lives forever holding its
storage.

- **Symptom:** none, until Durable Object storage climbs with no players.
- **Where to look:** object count in the dashboard against plausible concurrent games.

### 3. The turn clock plays for somebody who is right there

The clock is scheduled from `Date.now()` in the Worker. If a deadline is computed and the
alarm fires early, a present player has a move made for them.

- **Symptom:** "it played for me". Infuriating, and completely invisible on our side.
- **Where to look:** compare the `move` broadcast timestamp against `turnExpiresAt`.

### 4. A stale tab talking to a new protocol

`wrangler deploy` publishes the client and the Worker together, but a browser that loaded
the page an hour ago is still running the old JavaScript against the new Worker.

- **Symptom:** one player's moves are rejected and nobody else's are.
- **What catches it:** `PROTOCOL_VERSION` in the welcome message — **and nothing currently
  reads it.** That is a known gap; it is the cheapest place to add a real check.

### 5. Room creation abuse

`POST /api/rooms` is unauthenticated on purpose — requiring auth defeats an invite link. A
script can create Durable Objects faster than players can fill them.

- **Symptom:** quota consumed with no players. The service **suspends rather than bills**,
  so the first sign is the game being down, not an invoice.
- **Where to look:** Durable Object count, and the `POST /api/rooms` rate in Workers Logs.
  A healthy ratio is roughly one room created per two or more sockets joined; far more
  rooms than joins is the signature.

### 6. A cascade that does not terminate

A board wholly owned by one player is a mathematically infinite chain. `applyMove`'s
single-owner guard is the only thing that stops it, and `MAX_WAVES` throws if that guard
is ever broken.

- **Symptom locally:** a frozen tab. **In a room:** the Durable Object is wedged and every
  player in it sees nothing happen at all.
- **What catches it:** a test per shape and size in `packages/engine/test/soak.test.ts`.
  In production it would appear as an exception in Workers Logs from one object.

### 7. Hibernation loses a socket's identity

Seats are attached to sockets with `serializeAttachment`. If a socket comes back from
hibernation without its attachment, `playerFor` returns `undefined` and **every message
from that player is dropped without a reply**.

- **Symptom:** one player's taps do nothing. No error reaches them, because the code path
  that would send an error is the one that needs the identity.
- ⚠️ This is the one failure with no signal at all. If a player reports "my clicks do
  nothing" and their connection is open, look here first.

## If you add one thing

Count `OUT_OF_SYNC` errors and rooms-created-versus-sockets-joined. Those two numbers
cover failures 1 and 5, which are the two most likely to actually happen.
