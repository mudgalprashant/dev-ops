---
title: Environment variable matrix
status: current
last_updated: 2026-08-22
---

# Environment variable matrix

Every variable, which app needs it, whether it is a secret, and **how to verify it is
right**. Names only — never a value, in this file or any other.

Where the secret values actually live, and how to rotate them: **[secrets.md](secrets.md)**.

Authority for what the backend actually reads: `drovi-backend/src/main/resources/application.yaml`
and `render.yaml`.

## Backend — drovi-backend (Spring Boot 4)

### Runtime

| Variable | Req in | Secret | Verify |
| --- | --- | --- | --- |
| `DROVI_PORT` | all | | `curl localhost:$DROVI_PORT/actuator/health` → `UP` |
| `DROVI_LOG_LEVEL` | all | | logs appear at the set level |
| `DROVI_PUBLIC_BASE_URL` | prod | | origin only, no path. It is what users paste before `/s/<key>` |

### PostgreSQL (Supabase, session pooler)

| Variable | Req in | Secret | Verify |
| --- | --- | --- | --- |
| `DROVI_DB_URL` | all | | app starts and Flyway logs 2 migrations applied. **Port must be 5432, not 6543** |
| `DROVI_DB_USERNAME` | all | | form is `postgres.<project-ref>` for the pooler |
| `DROVI_DB_PASSWORD` | all | ✅ | connect succeeds (no `password authentication failed`) |
| `DROVI_DB_POOL_MAX` | all | | Hikari logs the pool size at boot. **2 on Render free** — the pooler is shared and a big pool starves every other client of the project |

⚠️ Three Supabase traps, all of which fail confusingly: direct connections are IPv6-only
without a paid add-on; transaction mode (6543) has no prepared statements, which Hibernate
and Flyway both need; and Flyway's advisory lock is connection-scoped. **Session mode,
port 5432.**

### Model provider — Anthropic

| Variable | Req in | Secret | Verify |
| --- | --- | --- | --- |
| `DROVI_ANTHROPIC_API_KEY` | prod | ✅ | a generation completes and writes an `ai_call` row with `status = 'OK'` |

The base URL, model, auth header name and max output tokens are **columns in
`ai_provider_config`**, not env vars — switching provider or model must be an `UPDATE`, not
a release (#38). The row names which env var holds the key (`api_key_env_var`), so a
database backup is never a credential leak.

⚠️ Until the key is set, leave `ai_provider_config.active = false`. A provider marked
active with no key fails every call at request time instead of at startup, which is the
worse failure.

### Identity — Firebase

| Variable | Req in | Secret | Verify |
| --- | --- | --- | --- |
| `DROVI_FIREBASE_PROJECT_ID` | prod | **no** | `GET /api/v1/me` with a valid ID token returns 200; one minted for another Firebase project is rejected |

**One variable, and it is not a secret.** Verifying a Firebase ID token needs no
service-account credential: the token is an RS256 JWT and Google publishes the signing keys
as a JWK set (ADR-0006). `DROVI_FIREBASE_CREDENTIALS_B64` is **retired** — delete it
wherever it is set.

⚠️ **Absence is meaningful.** With no project id there is no token decoder, and every
console route returns `AUTH_NOT_CONFIGURED` (503). That is the intended fail-closed state,
not a bug. Sandboxes are unaffected — they authenticate with project API keys.

⚠️ **A wrong project id does not fail loudly.** Tokens from your real project will simply be
rejected as having the wrong audience, which looks like "my login is broken". Check this
value first when authentication mysteriously fails.

## Console — drovi-frontend (Next.js, not yet built)

| Variable | Req in | Secret | Notes |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | all | | the console API origin |
| `NEXT_PUBLIC_FIREBASE_*` | all | | the **web** config — publishable by design, not secret |

INVARIANT: anything prefixed `NEXT_PUBLIC_` ships to the browser and is public. The model
provider key, database credentials and the Firebase **service account** must never appear
here.

## CI — GitHub Actions

| Variable | Where | Secret | Notes |
| --- | --- | --- | --- |
| `RENDER_DEPLOY_HOOK_URL` | repo → Environment `production` | ✅ | Must live in a GitHub **Environment** with required reviewers, not a repo-wide secret — a PR build must never be able to read it |

CI needs **no database variables**: integration tests start their own real Postgres from a
Gradle dependency.

## Retired — delete on sight

These belonged to the flight-alerts product and mean nothing now. If you find one set
anywhere, remove it:

`DROVI_FIREBASE_CREDENTIALS_B64` (retired 2026-08-23 by ADR-0006 — verification needs only
the project id), `DROVI_AERODATABOX_BASE_URL`, `DROVI_AERODATABOX_API_KEY`, `DROVI_WEBHOOK_PUBLIC_BASE_URL`,
`DROVI_VENDOR_WEBHOOK_TOKEN`, `DROVI_VENDOR_WEBHOOK_SECRET`, `DROVI_EXPO_ACCESS_TOKEN`,
`DROVI_REDIS_URL`, `DROVI_REDIS_PASSWORD`, `DROVI_JWT_SIGNING_KEY`, `DROVI_JWT_KEY_ID`,
`DROVI_ACCESS_TOKEN_TTL`, `DROVI_REFRESH_TOKEN_TTL`, `DROVI_EMAIL_*`, `DROVI_SMS_*`.

`DROVI_JWT_SIGNING_KEY` deserves a specific note: Drovi no longer mints tokens at all
(#7). If one exists, it is an unused credential that can only ever be a liability —
delete it rather than rotating it.

## Rules

- **Never a value in this repo**, including a placeholder that looks real. Use
  `CHANGE_ME_LOCAL_ONLY`.
- The app **fails to start** when a required variable is missing — never a silent default.
- Anything governing spend belongs in `app_config`, not in an env var, so it can be
  changed during an incident without a deploy.
