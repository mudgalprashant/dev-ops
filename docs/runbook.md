---
title: Runbook — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Runbook

One procedure per silent failure in [observability.md](observability.md). Each starts with
how to confirm it, because acting on the wrong diagnosis here is cheap to do and expensive
to undo.

---

## Deploy

```bash
pnpm install
pnpm test                                    # 29 engine tests — must be green
pnpm --filter @cellbreak/web build           # REQUIRED: the Worker serves apps/web/dist
pnpm --filter @cellbreak/server deploy
```

⚠️ **Building the client is not optional and not automatic.** `wrangler deploy` uploads
whatever is in `apps/web/dist` at that moment. Skip the build and you ship the previous
client against the new Worker — which is silent failure #4, self-inflicted. The CI workflow
does both in order; do the same by hand.

**Verify:** load the site, create a room, open the invite link in a second tab, play one
move both ways. `apps/web/test/online-check.mjs` does exactly this — point it at the
deployment with `CELLBREAK_ORIGIN=https://<worker>.workers.dev`.

## Roll back

```bash
cd apps/server && pnpm exec wrangler rollback     # previous Worker version
```

⚠️ **The rollback takes the Worker back but not necessarily the client bundle**, since the
assets ship with the deploy. Confirm the page's script hash changed too; if it did not,
re-deploy from the previous commit rather than trusting the rollback.

**Games in flight do not survive it.** A Worker version change restarts Durable Objects,
so rooms reload from storage — players reconnect and resume, but anyone mid-cascade sees
the board jump to the settled position. This is correct, and it looks like a glitch.

---

## "It played my turn for me"

Silent failure #3.

1. Confirm: in Workers Logs, find the room's `move` broadcast and compare its timestamp
   with the `turnExpiresAt` the previous move carried. A move *at or after* the deadline is
   the clock working as designed and the player was slower than they thought.
2. If it fired **before** the deadline, that is a real bug in `nextDeadline` /
   `scheduleAlarm` in `apps/server/src/room.ts`.
3. Mitigation without a deploy: none — the clock is per-room config, set by the host. The
   host can start the next game with the clock off.

## "My clicks do nothing"

Silent failure #7 — hibernation lost the socket's identity.

1. Confirm it is not simply not their turn: ask what the footer says.
2. Ask them to **refresh**. The seat token in `sessionStorage` rejoins the same seat, and a
   fresh socket carries a fresh attachment. This fixes it every time, which is also how you
   confirm the diagnosis.
3. If a refresh does *not* fix it, it is not this — look at `OUT_OF_SYNC` instead.

## Boards disagree between players

Silent failure #1.

1. Confirm: `wrangler tail` and watch for `OUT_OF_SYNC`. Near-zero is normal; a burst is not.
2. **If it started right after a deploy, that is the cause** — old clients, new engine. It
   resolves as players refresh. To force it, deploy again; the assets change and cached
   pages revalidate.
3. If it is *not* deploy-adjacent, it is an engine bug, and it is serious. Reproduce with
   the move sequence from the logs against `packages/engine`, and add the case to
   `game.test.ts` before fixing anything.

## Rooms exist with nobody in them

Silent failure #2.

1. Confirm: Durable Object count in the dashboard, against plausible concurrent games.
2. Look for exceptions from `alarm()` in Workers Logs — a throw before `scheduleAlarm()`
   breaks the chain permanently for that object.
3. Objects with no alarm and no sockets are inert but hold storage. They do not self-heal;
   the fix is a deploy that re-arms on the next request.

## Quota is draining with no players

Silent failure #5 — room-creation abuse.

1. Confirm: in Workers Logs, compare `POST /api/rooms` count against WebSocket connections.
   Far more rooms than joins is the signature.
2. **There is no rate limit today.** The immediate levers, in order of how quickly they can
   be applied:
   - a Cloudflare **WAF rate-limiting rule** on `POST /api/rooms` — dashboard only, no
     deploy, effective in seconds. **This is the first thing to reach for.**
   - shorten `IDLE_MS` in `room.ts` so unused rooms evict sooner.
3. Remember the failure mode is **suspension, not a bill**. There is no card on the
   account, so the worst case is downtime.

## The site is down

1. Cloudflare status page first — it is more often them than us, and there is nothing to do.
2. Workers Logs for exceptions at the top level of `fetch`.
3. If the Worker is fine and only the page is blank, the assets did not upload: check the
   deploy run's output for the asset count, then redeploy after building the client.

---

## What there is no procedure for

No database to restore, no migration to reverse, no secret in the app to rotate mid-
incident, no queue to drain. That is the payoff of [free-stack.md](free-stack.md)'s "no
database" decision, and it is why this runbook is short.

The one credential, `CLOUDFLARE_API_TOKEN`, is rotated per [secrets.md](secrets.md) — and
because it is CI-only, rotating it never interrupts a running game.
