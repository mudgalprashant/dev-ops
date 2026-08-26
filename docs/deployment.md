---
title: Deployment — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend]
---

# Deployment — bidceleb

Two pieces, two hosts, both free and neither needing a card.

| Piece | Host | Why |
| --- | --- | --- |
| Board (`bidceleb-frontend`) | **Firebase Hosting**, static export → <https://bidceleb.web.app> | free on Spark with no card; the output is plain files, so moving later is a redeploy |
| API (`bidceleb-backend`) | **Render** free web service, from the `Dockerfile` | suspends rather than bills; no card |

They are on **different origins**, so the API's CORS allowlist
(`BIDCELEB_CORS_ALLOWED_ORIGINS`) is load-bearing — without it the deployed board cannot
call the API at all, and the failure appears only in the browser console.

## Deploying the board

```bash
# The API must be reachable at BUILD time: generateStaticParams enumerates the celebrity
# pages and generateMetadata gives each its own title.
BIDCELEB_BUILD_API_BASE=http://localhost:8080 \
NEXT_PUBLIC_API_BASE_URL=https://bidceleb-backend.onrender.com \
npm run build
firebase deploy --only hosting --project bidceleb
```

⚠️ **A celebrity added after a deploy has no page until the next one.** The board picks new
entries up immediately (it fetches at runtime); only `/x/<slug>` and `/boost/<slug>` are
frozen at build.

### What the free tier costs here, and when to leave it

Firebase's free plan serves static files only, so there is no server rendering and link
previews carry no live figures. The upgrade is **Firebase App Hosting**, which runs the SSR
build properly and requires Blaze and a card — the right move once boost revenue makes a
billing account unremarkable. Nothing in the code blocks it.

## Deploying the API

Render → **New → Blueprint** → pick `bidceleb-backend`; it reads `render.yaml` and prompts
for every `sync: false` value. Everything below is the generic mechanism.

---

# The mechanism

## Environments

| Env | Where | Database | Deploy trigger |
| --- | --- | --- | --- |
| local | your machine | a local one, or none — tests start their own | run the app directly |
| test | the CI runner | a real database the test suite starts itself | every push |
| prod | one free web service on the host | the managed free tier | push to the release branch |

**There is deliberately no staging.** A second service and a second database would consume
the free allowances production depends on. When a change is risky enough to need staging,
that is a signal about the change, not about the environments.

## How a deploy happens

1. The release PR merges into the release branch.
2. The host builds the `Dockerfile` (multi-stage; the artifact is compiled inside the image).
3. The container starts as a **non-root** user; pending migrations apply at startup.
4. A health check gates the switchover.

> **The `Dockerfile` *is* the deploy path, not a portability hatch.** Keeping deployment as
> a Dockerfile rather than provider-specific configuration is what makes changing host
> cheap — and hosts do get changed.

## One instance means no blue-green

The new container starts while the old one is still serving. Two consequences, both
non-negotiable:

- **A migration must be compatible with the previously running version.** Add a column
  before anything writes to it; never rename or drop in the same release that stops using
  it. Two releases, always.
- **INVARIANT: migrations are forward-only. Never roll back a migration; write a
  fix-forward one.** Rolling the *image* back is safe only if the older image tolerates the
  newer schema — which is exactly what the previous rule guarantees.

## Resource tuning on a small instance

At 512 MB and a fraction of a CPU, the defaults are wrong in three specific ways:

| Setting | Why |
| --- | --- |
| Cap the heap by **percentage of the cgroup limit**, not an absolute figure | reads the container's actual limit, so changing plan needs no rebuild |
| **SerialGC** below ~2 GB | a concurrent collector's background threads cost more on a fraction of a CPU than its pauses save |
| **Stop tiered compilation at level 1** | skips the optimising compiler: slower steady state, much faster startup — and on an instance that spins down, startup is what users experience |
| A **very small** connection pool | sized against the database's connection limit, not expected load |

## Cold starts are a product problem, not an ops one

A free instance spins down after ~15 minutes idle and takes 30–60 seconds to come back. A
browser user sees a slow page; **a machine calling your API sees a timeout.** If anything
automated depends on the service, a keep-alive ping is load-bearing infrastructure, not
hygiene — and it doubles as what keeps a free database from pausing after a week idle.

Budget it: 750 instance-hours a month against 744 hours in a 31-day month leaves about six
hours of margin for redeploys. Running two services on one free account does not fit.

## Rollback

Host dashboard → the service → **Deploys** → redeploy a previous successful build.
**Never roll back a migration.**
