---
title: Free-tier budget — every service, what we get, and what runs out first
status: current
last_updated: 2026-08-22
---

# Free-tier budget

One row per service we depend on. **Verified** means checked against the vendor's
own docs in August 2026; **unverified** means it could not be confirmed from public
documentation and must be checked at signup.

## Infrastructure

| Purpose | Service | Free tier | Verified |
| --- | --- | --- | --- |
| **API hosting** | **Render** (Free web service) | **512 MB RAM · 0.1 CPU · 750 instance-hours/month** · 100 GB bandwidth · spins down after 15 min idle · **no card, suspends rather than bills** | ✅ |
| **Database** | **Supabase** (Free) | 500 MB database · 500 MB RAM (shared) · 1 GB file storage · 5 GB egress/mo · unlimited API requests · 2 projects | ✅ |
| **Auth** | **Firebase Authentication** (Spark) | **3,000 daily active users** · email/password + Google + Apple included · no card | ✅ |
| **CI** | **GitHub Actions** (Free) | Unlimited for public repos · 2,000 min/month for private · Postgres for tests via `services:` containers on the runner | ✅ |
| **Source hosting** | **GitHub** (Free) | Unlimited private repos | ✅ |
| **Error tracking** | **Sentry** (Developer) | 5,000 errors/month · 1 user | ⚠️ from memory |
| **Uptime monitoring** | **UptimeRobot** (Free) | 50 monitors · 5-minute interval | ⚠️ from memory |
| **Model inference** | **Anthropic** | **NOT FREE** — metered per token. The only per-use cost in the stack | ✅ |
| **Console hosting** | **Render** or **Cloudflare Pages** | Free static/SSR hosting. **Not Vercel** — Hobby is non-commercial only (#29) | ✅ |

## Not used, and why

| Purpose | Status |
| --- | --- |
| Cache / Redis | **Not used in v1.** Firebase took sessions; at one instance an in-JVM Caffeine cache is more correct than a network hop. Returns when we run a second instance |
| Queue broker | **Not used.** A Postgres table with `next_attempt_at` is the queue. Retry state must survive a restart |
| Mobile builds / EAS | **Gone.** Drovi's client is a web console, not a mobile app (#31) |
| Email / SMS providers | **Not used.** Drovi sends no messages |
| Local Postgres | **Not needed.** Supabase is remote for every environment; tests run an embedded Postgres that needs nothing installed |

## What runs out first

In the order we will actually hit them:

1. **Supabase 500 MB.** ⚠️ **The first wall, and the nearest one.** `mock_request_log`
   writes a row per served call and **its purge job is not written**, so today it grows
   without bound. Sandbox record data is capped per project by plan; the log is not
   capped by anything. Writing that purge is the single highest-value ops task
   outstanding.
2. **Anthropic credits.** The only real money. Every control — the kill switch, the
   platform and per-account daily caps, the per-call ledger, per-purpose model routing —
   exists for this line. Unlike the others it can be exhausted in *minutes* by a loop,
   which is why the caps live in the database rather than in config.
3. **Render's 512 MB.** The tightest technical limit and the least proven. Heap is
   capped at 65% with SerialGC and C2 disabled. If it OOMs the fix is $7/month.
4. **Render's 750 instance-hours.** 744 hours in a 31-day month, so staying awake fits —
   with roughly six hours of margin for redeploys.
5. **Firebase 3,000 DAU.** Comfortable for a long time. Moving to Blaze raises it to
   50,000 MAU free but requires a card.

## Traps that are not about quota

- **Supabase free projects pause after 7 days with zero requests.** The uptime
  monitor is not ops hygiene — it is what keeps the database awake.
- **Firebase phone/SMS auth is billed per message** even inside the free MAU
  allowance. Email/password and Google are not. Do not enable phone sign-in casually.
- **Render free suspends; it never bills.** That is why it was chosen over hosts
  with better specifications. There is no card on the account to charge.
- **Vercel Hobby is non-commercial only.** A freemium product with a paid tier
  breaches it the day that tier goes live. Ruled out on terms, not capability.
- **Render's cold start reads as a timeout to a machine.** A sandbox is called by
  someone else's *running application*, not by a person who will wait 30 seconds. The
  keep-alive is load-bearing, not hygiene.
- **Oracle Cloud was ruled out by signup, not by specification.** Its fraud check
  rejects legitimate cards with no appeal path. Do not spend another evening on it.
- **GCP was ruled out on silent-billing risk.** A Balanced boot disk instead of
  Standard, or an egress overage, bills without warning. Workable with a budget
  alert, but not worth the vigilance for a side project.
