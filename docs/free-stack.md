---
title: The free stack — what we use for each concern, and what it costs
status: current
last_updated: 2026-08-22
---

# The free stack

Constraint: **build everything on free tooling.** Exactly one thing resists that, and it
is named honestly below rather than hidden in a footnote.

## Choices

| Concern | Choice | Cost | Why this one |
| --- | --- | --- | --- |
| App host | **Render** (Free web service) | Free — **no card, and it suspends rather than bills** | Chosen for its billing model first and its specs second. 512 MB RAM · 0.1 CPU · 750 instance-hours/month · spins down after 15 min idle. Marginal for a JVM, which is why the container caps the heap at 65% of 512 MB with SerialGC and C2 disabled |
| TLS + reverse proxy | Render provides both | Free | A managed `*.onrender.com` hostname with a certificate. Nothing to configure, no DNS name to buy |
| Database | **Supabase** free — 500 MB, via the **Supavisor session pooler** | Free | Managed, with backups and a SQL editor. Three connection traps, all of which fail confusingly: direct connections are **IPv6-only** without a paid add-on; **transaction mode (6543) has no prepared statements**, which Hibernate and Flyway both need; and Flyway's advisory lock is connection-scoped, so transaction pooling can release it on a different backend. **Use session mode, port 5432.** Free projects pause after **7 days with zero requests** — the keep-alive prevents that |
| Cache | **Caffeine**, in-JVM | Free | One instance, so an in-process cache has no network hop, no serialisation and nothing extra to keep alive. No Redis (#13) |
| Scheduling | **In-process `@Scheduled`** + Supabase `pg_cron` keep-alive | Free | Always-on and single-instance. The 5-minute keep-alive (#30) prevents Render's idle spin-down: 744 h/month against a 750 h allowance |
| Auth | **Firebase Authentication** | Free tier | Removes password hashing, token rotation, reuse detection and session storage from our scope entirely — a large amount of security-critical code we do not own. **Not yet wired** |
| **Model provider** | **Google Gemini** | **Free tier — no card** | 15 req/min, 1,500 req/day. ⚠️ the free tier trains on your content — see below |
| CI | **GitHub Actions** | Free (2 000 min/mo private) | |
| Integration tests | **zonky embedded-postgres** | Free | Pulls a real Postgres binary as a Gradle dependency and runs it in-process. **No Docker, nothing to install.** The schema uses partial indexes, generated columns, `jsonb`, composite FKs and a trigger — none of which H2 implements |
| Local Postgres | **Postgres.app**, only if you want one | Free | Not needed for tests |
| Error tracking | **Sentry** free (5 k events/mo) | Free | Not wired |
| Uptime | **UptimeRobot** / **cron-job.org** free | Free | Also the keep-alive mechanism |
| Console | **Next.js + React + TypeScript**, on **Render or Cloudflare** | Free tier | Not Vercel: its Hobby plan is non-commercial only (#29), so a paid tier would breach the terms. Decision #41 / ADR-0005 |

## The one thing that can still cost money

Gemini's free tier needs no card and does not expire, so nothing here bills today. That
does **not** make the spend controls optional — the free tier is a rate limit, not a
guarantee, and the day we move to paid (see the warning below) inference becomes the only
per-use cost in the stack.

**Two free-tier limits shape the design:**

| | Free | Consequence |
| --- | --- | --- |
| 15 requests/minute | ⚠️ | generation is bursty — research → spec → seed is many calls in a row. The job runner must pace itself rather than fan out |
| 1,500 requests/day | | comfortable for development |

⚠️ **The free tier trains on your content.** Google's terms say content sent to the
non-paid tier, and the responses, may be used to improve Google's products, and **human
reviewers may read it**. Generation sends a user's prompts and whatever product docs they
supply — which for a real customer may be an internal API. **Move to the paid tier before
any real user's content passes through generation.** Fine on capability, wrong on terms —
the same shape of problem as Vercel (#29). Recorded in ADR-0008.

So the model provider is where every cost control goes:

| Control | Where | Effect |
| --- | --- | --- |
| **Kill switch** | `app_config.ai.enabled` | Fails closed with `CAPPED` instead of calling the provider. Stops *spending*, never *serving* — sandboxes keep working |
| **Platform daily cap** | `ai.daily.cost.cap.micros` | A bug loops; a cap means it loops cheaply |
| **Per-account daily cap** | `ai.account.daily.cost.cap.micros` | One account cannot exhaust the platform cap |
| **Per-call ledger** | `ai_call` | You cannot control a cost you cannot see. Written whether the call succeeded or not — a success-only ledger under-reports exactly when spend is running away |
| **Effective-dated pricing** | `model_pricing` | Cost recorded at the rate in force when the call happened, so a price change never restates a past month |
| **Per-purpose model routing** | `app_config.ai.model.*` | Move one purpose to a cheaper model without a deploy. `SEED` is the highest-volume purpose and the obvious first candidate |
| **Freemium maps cost to revenue** | `plan_catalog` | Free tier caps projects, storage, requests, tokens and generations |

Every one of these lives **in the database**, so they can be changed during an incident at
3am without waiting for a build.

## The other metered resource: storage

Supabase free is 500 MB, and sandbox data is user-controlled. `sandbox_record` is capped
per project by plan (`max_stored_bytes_per_project`), enforced on write against
trigger-maintained counters.

⚠️ **`mock_request_log` is the fastest-growing table** — one row per served call — and its
retention purge **is not written**. `plan_catalog.log_retention_days` is currently
decorative. This is the most likely cause of the first storage surprise.

## No Redis

Redis was in the original design for cache, rate limits, session storage and config cache.
Firebase owns sessions; cache and config cache are in-process concerns at one instance.
Rate limiting is not built. Adding Redis back would mean a network hop, a serialisation
format and another free tier to stay inside, for no gain at this size.
