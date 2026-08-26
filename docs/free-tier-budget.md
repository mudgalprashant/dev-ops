---
title: Free-tier budget — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend]
---

# Free-tier budget — bidceleb

The ceilings of the default stack are canonical on `main`. This file answers the only
question that matters: **what runs out first, for this product.**

The shape of this product's load is unusual and drives the whole ordering: it is
**read-heavy, public, and spiky**. Almost every visitor reads the board and never pays. The
traffic arrives in bursts, because the growth loop is somebody losing their position and
posting about it. Long quiet periods punctuated by sudden bursts is the worst possible
pattern for a free tier, and every row below follows from it.

| # | Limit | Ceiling | What consumes it | At the wall | Mitigation |
| --- | --- | --- | --- | --- | --- |
| 1 | **Render cold start** | ~15 min idle → 30–60 s wake | quiet periods between bursts | the burst arrives at a sleeping service and the share link looks broken | the `pg_cron` keep-alive. **Load-bearing, not hygiene** |
| 2 | **Render 512 MB / 0.1 CPU** | hard | a burst of concurrent leaderboard reads | OOM, or latency bad enough that people leave | cache the leaderboard aggressively; it is the same response for everyone |
| 3 | **Supabase 500 MB** | hard | `payment_event` (raw webhook payloads) | writes fail — including settlements | **write the purge job in the payments slice**, not after |
| 4 | **Render 750 instance-hours** | 744 h in a 31-day month | always-on keep-alive | service suspends | ~6 h of margin. One free service fits; two do not |
| 5 | **Supabase egress 5 GB** | soft | leaderboard queries | | the cache in row 2 also fixes this |
| 6 | **Firebase 3,000 DAU** | soft | sign-in only | | **sign-in is optional here** — most visitors never authenticate, so this is far away |

## Why cold start is number one, and not an inconvenience

For most products a cold start is a slow first page. Here it is the growth loop failing at
its most valuable moment: someone has just been outbid, has posted the link, and thirty
people click it at once. They arrive at a service that takes 45 seconds to answer.

It is also the cheapest thing on this list to fix — one `pg_cron` job — which is exactly
why it gets skipped. Treat the keep-alive as infrastructure with an owner and a check, not
as a setup step that was done once.

## Why `payment_event` and not a request log

This product does not write a row per served request; the board is a read. What it does
write is a row per webhook, with the raw payload, and those payloads are large.

The retention window is not a tuning knob: **keep at least 90 days**, because that is the
usual chargeback window and those rows are the evidence. So the purge job cannot simply be
"delete old rows" — it has to keep the reconciliation window intact. Write it with the
payments slice, while the reasoning is in front of you.

⚠️ A retention setting with no job behind it is decorative, and it is always discovered
during an incident.

## What is deliberately not a constraint here

- **No AI spend.** Nothing in this product calls a model, so the entire category of
  runaway-spend controls that dominates a generative product does not apply. The money risk
  here runs the *other* way: money coming in and not being honoured.
- **No per-request log table.** The board is cached; the ledger is the only thing that grows
  with success.
- **Payment provider fees are a cost of revenue, not a free-tier limit.** They scale with
  income and never suspend anything.

## Review triggers

Re-read this when the board takes 10× the boosts it does today, when a category page
becomes as popular as `ALL`, or when anything starts writing a row per page view. The first
two change row 2; the third would insert a new row 1.
