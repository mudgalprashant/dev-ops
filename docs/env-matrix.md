---
title: Environment matrix — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend, dev-ops]
---

# Environment matrix — bidceleb

**Names only — never a value, in this file or any other.** The authority for what the
backend actually reads is `bidceleb-backend/src/main/resources/application.yaml` and
`render.yaml`.

The three rules, the naming convention and the Postgres pooler traps are canonical on
`main` — see that branch's `docs/env-matrix.md`. This file is the inventory.

## Backend — `bidceleb-backend`

### Runtime

| Variable | local | test | prod | Secret | Purpose / verify |
| --- | --- | --- | --- | --- | --- |
| `BIDCELEB_PORT` | ✅ | | ✅ | ❌ | 8080. The host maps 443 → this; 8080 is never public |
| `BIDCELEB_LOG_LEVEL` | ✅ | | ✅ | ❌ | `INFO`. `DEBUG` on a 0.1-CPU instance costs real latency |
| `BIDCELEB_PUBLIC_BASE_URL` | ✅ | | ✅ | ❌ | **Origin only, no trailing slash, no path.** The API's own address. Verify: a checkout redirect lands back on the right host |
| `BIDCELEB_WEB_BASE_URL` | ✅ | | ✅ | ❌ | Where the board lives — `https://bidceleb.web.app`. Checkout returns here, not to the API |
| `BIDCELEB_CORS_ALLOWED_ORIGINS` | ✅ | | ✅ | ❌ | Comma-separated allowlist. **Never `*`** — see below |

### Database — Supabase, session pooler

| Variable | local | test | prod | Secret | Purpose / verify |
| --- | --- | --- | --- | --- | --- |
| `BIDCELEB_DB_URL` | ✅ | | ✅ | 🟡 | JDBC form, port **5432**, `?sslmode=require` |
| `BIDCELEB_DB_USERNAME` | ✅ | | ✅ | 🟡 | `postgres.<project-ref>` — the qualified form |
| `BIDCELEB_DB_PASSWORD` | ✅ | | ✅ | ✅ | full read/write over the boost ledger |
| `BIDCELEB_DB_POOL_MAX` | ✅ | | ✅ | ❌ | **2 in production.** Sized against Supabase's limit, not load |

The test column is empty on purpose: **the test suite starts its own Postgres binary and
needs no database variables at all.** That is what lets CI run on a fork's pull request.

### Payments

| Variable | local | test | prod | Secret | Purpose / verify |
| --- | --- | --- | --- | --- | --- |
| `BIDCELEB_PAYMENT_API_KEY` | 🟡 | | ✅ | ✅ | Locally use the provider's **test-mode** key, never production's |
| `BIDCELEB_PAYMENT_WEBHOOK_SECRET` | 🟡 | | ✅ | ✅ **top-tier** | see below |

> ⚠️ **`BIDCELEB_PAYMENT_WEBHOOK_SECRET` is this project's highest-consequence credential.**
> Popularity is minted by exactly one code path: a signature-verified webhook. Whoever holds
> that secret can forge settlements and award unlimited popularity **without paying**, and
> the fraud is invisible in the payment provider's dashboard because no payment ever
> existed. The database password leaks *data*; this leaks the *product's integrity*, which
> is the thing customers are actually buying.
>
> Detection: `SELECT` settled boosts whose `payment_id` has no corresponding provider
> charge. Response: rotate the endpoint secret first, then reconcile the ledger against the
> provider's own record of charges — never against our own.

The provider's base URL, its display name and which env var holds its key are **columns in
`payment_provider_config`**, not environment variables: switching provider must be an
`UPDATE`, not a release. The row stores the env var's **name**, never its value, so a
database backup is never a credential leak.

⚠️ Until a real key is set, leave `payment_provider_config.active = false` for every live
provider and run the `STUB` adapter. A provider marked active with no key fails at request
time — that is, in front of a paying user — instead of at startup.

### Identity — Firebase (optional sign-in)

| Variable | local | test | prod | Secret | Purpose / verify |
| --- | --- | --- | --- | --- | --- |
| `BIDCELEB_FIREBASE_PROJECT_ID` | 🟡 | | ✅ | ❌ | **Not a secret** — ID tokens are verified as RS256 JWTs against Google's published JWK set |

**There is no Firebase service-account key anywhere in this system.** If a guide tells you
to download `firebase-adminsdk-*.json`, it does not apply here — skip it.

⚠️ **Absence is meaningful, and it is meaningful differently here than in a
sign-in-required product.** With no project id there is no token decoder, so the
*authenticated* routes (`/api/v1/me`, the admin queue) fail closed — but the board, the
leaderboard and **boosting still work**, because boosting never required an account. A
missing project id therefore does **not** take the product down; it silently removes
sign-in. Watch for it rather than relying on an outage to tell you.

⚠️ **A wrong project id does not fail loudly.** Tokens are rejected as wrong-audience,
which reads to a user as "my login is broken". Check this value first when sign-in
misbehaves.

> ⚠️ **`BIDCELEB_CORS_ALLOWED_ORIGINS` is not a formality.** The board is a static site on
> a different origin, so without it the deployed app cannot call the API at all — every
> request fails preflight and the board shows an error with nothing in the API's logs to
> explain it. In production it is
> `https://bidceleb.web.app,https://bidceleb.firebaseapp.com` (Firebase serves both).
>
> **Never a wildcard.** Nothing is authenticated yet, which makes `*` look harmless — but
> `/api/v1/checkout/boost` creates payment intents, and the moment sign-in lands a wildcard
> becomes a standing invitation. An allowlist that is correct now stays correct.

## Frontend — `bidceleb-frontend`

| Variable | Secret | Notes |
| --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | ❌ | Baked into the browser bundle at build time — changing it is a rebuild, not a config change |
| `BIDCELEB_BUILD_API_BASE` | ❌ | Build-time only, for `generateStaticParams` / `generateMetadata`. **Deliberately separate**: the build needs an API it can reach now (usually local); the bundle needs the address visitors use later |
| `NEXT_PUBLIC_FIREBASE_API_KEY` | ❌ | a Firebase web "API key" is an identifier, not a credential |
| `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN` | ❌ | |
| `NEXT_PUBLIC_FIREBASE_PROJECT_ID` | ❌ | |
| `NEXT_PUBLIC_FIREBASE_APP_ID` | ❌ | |

**INVARIANT: anything prefixed `NEXT_PUBLIC_` ships to the browser and is public.** The
payment API key, the webhook signing secret and the database credentials must never appear
here. There is no server-side secret in the frontend at all — every privileged action goes
through the backend.

## CI — GitHub Actions

**None.** The backend's tests start their own database; the frontend's build needs only
public values; and the host builds from the repo, so there is no deploy secret. If that
ever changes, the value goes in a GitHub **Environment** named `production` with required
reviewers — never a repository secret.

## Not environment variables — `app_config` rows

Anything governing **pricing, limits or a kill switch** lives in the database so it can be
changed mid-incident without a deploy:

```
payments.enabled                  master kill switch — stops TAKING money, never serving
boost.min.cents                   floor for a single boost, and the empty-tab target
boost.outbid.rate.bps             the increment rate in basis points (500 = 5%)
boost.outbid.cap.cents            the increment ceiling (5000 = $50)
boost.outbid.min.increment.cents  floor for the increment (100 = $1)
boost.max.cents                   sanity ceiling on one boost; above it, review manually
listing.price.cents               what adding a celebrity costs today
listing.list.price.cents          the struck-through "was" price
listing.enabled                   accept new submissions at all
leaderboard.page.size.max         paging ceiling
watch.enabled                     silences the alert.* WARN lines — the WARNING, not the limit
watch.settlement.gap.minutes      how long a created-but-unsettled boost may sit
watch.storage.budget.mb           database size at which alert.storage fires
```

## Retired — delete on sight

Nothing yet. When a variable stops being read, delete it from the host's dashboard and add
it here. An unused credential can only ever be a liability — delete it rather than rotating
it, and expect out-of-date guides to keep re-adding it.
