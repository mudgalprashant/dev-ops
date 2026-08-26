---
title: The free stack — what we use, and why
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# The free stack

The baseline every project starts from. A project's own branch records what it actually
chose and what it ruled out.

| Concern | Default choice | Why |
| --- | --- | --- |
| App host | **Render** free web service | **Chosen for its billing model first, specs second** — no card required, and hitting a limit *suspends the service rather than charging you* |
| TLS + reverse proxy | the host provides both | managed certificate, nothing to renew |
| Database | **Supabase** free Postgres, **session pooler** | 500 MB; pauses after 7 days of zero requests |
| Cache | in-process | no Redis at one instance: no network hop, nothing extra to keep alive |
| Scheduling | in-process scheduling + a database cron for the keep-alive | |
| Auth | **Firebase Authentication** | removes password hashing, token rotation, reuse detection and session storage from scope entirely |
| CI | **GitHub Actions** | unlimited minutes on public repos |
| Integration tests | a **real database binary as a build dependency** | no Docker required, and no dialect gap |
| Error tracking | **Sentry** free | |
| Uptime | **UptimeRobot** or **cron-job.org** | doubles as the keep-alive |
| Frontend | **Next.js + React + TypeScript**, hosted on Render or Cloudflare | |

## Ruled out, and why — these are conclusions, not open questions

| Thing | Why not |
| --- | --- |
| **Vercel Hobby** | non-commercial use only. A product with a paid tier breaches the terms. Ruled out on terms, not capability |
| **Oracle Cloud free tier** | ruled out by *signup*, not specification — its fraud check rejects legitimate cards with no appeal. Do not spend another evening on it |
| **GCP free tier** | silent-billing risk: the wrong boot-disk type or an egress overage bills without warning |
| **An in-memory database for tests** | a real schema uses partial indexes, generated columns, JSON types and triggers. A test suite that cannot express the schema is not testing the schema |
| **Docker for local development** | if the test suite starts its own database, there is nothing to install and nothing to start. A `make up` that boots an unused service is a trap, not a reference |
| **Kubernetes** | nothing to orchestrate at one instance. The `Dockerfile` *is* the deploy path |
| **An external secrets vault** | see [secrets.md](secrets.md) — it adds a bootstrap credential without removing a risk at this size |

## Traps that are not about quota

- **A free database pauses after ~7 days with zero requests.** The uptime monitor is what
  keeps it awake — that is infrastructure, not hygiene.
- **A free web service spins down after ~15 minutes idle**, and its cold start reads as a
  *timeout* to any machine calling it.
- **The host suspends rather than bills** — keep it that way by not putting a card on the
  account.
- **Phone/SMS authentication is billed per message** even inside a free monthly-active-user
  allowance. Do not enable phone sign-in casually.
- **A free AI tier may train on your content**, and human reviewers may read it. Move to a
  paid tier before any real customer's material passes through.

## The rule underneath all of it

Prefer the provider that **suspends** over the provider that **bills**. Every free tier
runs out; the only question is whether you find out from a dashboard or from a statement.
