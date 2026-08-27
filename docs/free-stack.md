---
title: The free stack — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# The free stack

Everything is free, and — the property that actually matters — **nothing here takes a
card**. Cloudflare's free plan is the whole hosting story.

| Concern | Choice | Why this one |
| --- | --- | --- |
| Client | **Vite + React 19 + TypeScript** | an SPA with nothing to server-render. Deviates from the baseline's Next.js default: there is no server-side data, no SEO surface beyond one page, and no route that benefits |
| Board rendering | **Canvas 2D** | a cascade moves dozens of orbs at 60fps. React owns the menus and the lobby; the board is one canvas and a `requestAnimationFrame` loop |
| Styling | plain CSS + custom properties | ~250 lines. A framework would be larger than the thing it styles |
| Multiplayer | **Cloudflare Durable Objects** (SQLite-backed) | one object per room *is* the room: single-threaded, authoritative, addressable by code. WebSocket hibernation means an idle room holds no compute |
| Hosting | **Cloudflare Workers static assets**, same Worker | one deploy, one origin, no CORS, no second service to keep alive |
| Database | **none** | nothing outlives a room. See below — this is the decision the rest of the stack falls out of |
| Auth | **none** | a nickname and a room code |
| Tests | **Vitest** on the engine | 29 tests over the rules; the two integration checks live in `apps/*/test` |
| CI/CD | **GitHub Actions** → `wrangler deploy` | unlimited minutes on a public repo |

## The decision everything else follows from: no database

Rooms are ephemeral. A game lasts minutes, nobody has an account, and there are no stats to
keep. So room state lives in its own Durable Object's storage and is deleted 30 minutes
after the last socket closes.

Removing the database removed, in one move: a provider to sign up for, a connection pooler
with three documented traps, a migration tool, a schema, a backup story, a 7-day idle-pause
failure mode, and the largest secret in the project. **The cheapest infrastructure is the
kind you did not deploy.**

## Why not the baseline's Render + Supabase + Firebase

Not a criticism of that stack — it is the right default for a product with users and data.
Cellbreak has neither.

| Baseline choice | Why not here |
| --- | --- |
| **Render free web service** | ⚠️ **disqualifying, not merely worse.** It spins down after 15 minutes idle and cold-starts in 30–60s. A player who taps a cell and waits 45 seconds has not experienced a cold start, they have experienced a broken game. Durable Objects have no such state |
| **Supabase** | there is nothing to persist |
| **Firebase Auth** | there is nobody to authenticate |
| **Vercel** | Hobby is non-commercial only — ruled out on terms, as it was before |
| **An uptime monitor** | its job in the baseline is keeping a free service awake. Nothing here sleeps, and nothing here pauses after 7 idle days |

## The one thing to actually watch

Not cost — **abuse**. `POST /api/rooms` creates a Durable Object with no authentication in
front of it, because requiring one would defeat the point of an invite link. That is a free
object-creation endpoint on the public internet.

It is bounded today by the room's own 30-minute self-deletion and by Cloudflare's per-plan
request ceiling, which suspends rather than bills. It is **not** bounded by anything we
wrote. See [observability.md](observability.md) for what this looks like when it happens
and [runbook.md](runbook.md) for what to do about it.
