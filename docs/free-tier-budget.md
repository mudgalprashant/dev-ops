---
title: Free-tier budget — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Free-tier budget

Sorted by **how soon you hit it**, which is the only ordering that helps.

| # | Limit | Ceiling (free) | What consumes it | At the wall | Mitigation |
| --- | --- | --- | --- | --- | --- |
| 1 | **Durable Object requests** | ~3M/month, with inbound WebSocket messages billed **20:1** → ~60M messages | every join, move, config change and reconnect | requests fail; **suspends, never bills** | the protocol already sends a cell index, not a board. Next lever is batching room broadcasts |
| 2 | **Worker requests** | 100k/day | page loads, asset fetches, `POST /api/rooms` | same | assets are cached at the edge; the realistic driver is room creation, not play |
| 3 | **Durable Object storage** | 1 GB | one small record per live room | writes fail | rooms self-delete 30 min after the last socket closes |
| 4 | **GitHub Actions** | unlimited public / 2,000 min per month private | CI and deploys | queued | keep the repo public; the whole run is ~2 minutes |

## What this means in practice

A full 8-player game is on the order of a few hundred WebSocket messages. Against ~60M
messages a month, the request ceiling is not a limit this game reaches by being *played* —
it is a limit it reaches by being *abused*.

⚠️ **So the real budget line is not in the table.** `POST /api/rooms` is unauthenticated by
design, and a script can create rooms far faster than players can fill them. Each one is a
Durable Object that lives for 30 minutes. That is the mechanism by which every row above
gets consumed at once, and it is the thing to watch. See [observability.md](observability.md).

## Verified

Checked against Cloudflare's own documentation in August 2026: Durable Objects have been on
the free plan since April 2025, SQLite-backed, and inbound WebSocket messages bill at 20:1.
Re-check before relying on the headroom; free tiers move.

## Reviewing this

Re-read when a change starts sending messages per *frame* rather than per *move* — a
spectator feed, a live cursor, a chat — because that is what turns row 1 from theoretical
into the first wall.
