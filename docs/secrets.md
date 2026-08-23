---
title: Secrets — where they live, how to set them, how to rotate them
status: current
last_updated: 2026-08-23
applies_to: [drovi-backend, drovi-frontend, dev-ops]
---

# Secrets

## The rule

> **No secret value is ever written to a file in any repo, or to any file on a developer's
> machine that is not already gitignored and transient.**

Secrets live in exactly two places, both encrypted at rest and neither in git:

| Store | Holds | Who can read it |
| --- | --- | --- |
| **Render → Environment** | everything production needs | you, in the Render dashboard |
| **GitHub → Environment `production`** | anything CI needs to deploy | workflows on protected branches, with required reviewers |

## Why no external vault

An external vault (Doppler, Infisical, HCP Vault) was considered and **not** adopted —
see `drovi-backend/docs/00-overview/decisions/ADR-0007-secrets-without-a-vault.md`.

The short version: at this size a vault adds a moving part and a new bootstrap credential
without removing a real risk, because Render's environment is already encrypted secret
storage. Revisit when any of the triggers in that ADR fire.

## The bootstrap problem, and why we do not have one

Any vault needs a credential to read it, and that credential must live somewhere — so
"no secrets anywhere" is never achievable; you only choose *where the last one lives*.

With this model there is **no vault client and no vault token at all**. The application
reads ordinary environment variables that Render injects into the container. The last
credential is your Render login, protected by MFA, and it is never on disk.

## Not everything called "config" is a secret

Treating a non-secret as secret is its own cost: it ends up in one dashboard, undocumented,
and nobody can reproduce a local run.

| Value | Secret? | Why |
| --- | --- | --- |
| `DROVI_DB_PASSWORD` | ✅ | full read/write over every tenant's data |
| `DROVI_GEMINI_API_KEY` | ✅ | metered spend with no natural ceiling |
| `DROVI_DB_URL`, `DROVI_DB_USERNAME` | 🟡 | not secret alone, but they name the target — keep them beside the password |
| `DROVI_FIREBASE_PROJECT_ID` | ❌ | **not a secret.** Verifying a Firebase ID token needs only the project id (ADR-0006); it is also visible in any web client's config |
| `DROVI_PUBLIC_BASE_URL`, `DROVI_PORT`, `DROVI_LOG_LEVEL` | ❌ | plain configuration |

There is **no Firebase service-account key anywhere in this system.** If a guide tells you
to download `firebase-adminsdk-*.json`, that guide predates ADR-0006 — skip it.

---

## Step 1 — Production secrets, in Render

Render is the source of truth for anything the running service needs.

1. Render dashboard → your service → **Environment** (left sidebar).
2. **Add Environment Variable** for each row in `env-matrix.md` marked *Secret*.
3. **Save changes.** Render restarts the service; a restart is the only way a changed
   value takes effect.

`render.yaml` already declares each one with `sync: false`, which means *"prompt me, never
store this in git."* That is why the repo can describe every variable without holding a
single value.

⚠️ **Never paste a secret into `render.yaml`, a commit message, a PR description, or a
chat.** Anything you paste is in a log somewhere.

## Step 2 — CI secrets, in a GitHub Environment

Only needed once a workflow has to reach something protected. Do it as a GitHub
**Environment**, never a repository secret.

1. Repo → **Settings → Environments → New environment** → name it `production`.
2. **Deployment protection rules** → tick **Required reviewers** → add yourself.
3. **Environment secrets → Add secret** for each CI needs.
4. In the workflow, name the environment so the secrets are reachable:

   ```yaml
   jobs:
     deploy:
       environment: production      # ← without this, the secrets are invisible
   ```

**Why an Environment and not a repository secret:** a repository secret is readable by
*any* workflow, including one added in a pull request from a fork. An attacker's first move
against a public repo is a PR that adds a workflow printing every secret it can see. An
Environment with required reviewers cannot be reached that way.

Today the backend needs **no** deploy secret: Render builds from the repo itself.

## Step 3 — Local development

**The policy: production credentials never land on a laptop.**

Local development does not need them, and this is worth internalising because it removes
the whole class of "my machine got compromised" incidents:

| Want to… | Needs | Secret? |
| --- | --- | --- |
| Run the tests | nothing — they start their own Postgres | none |
| Run the app against a local DB | a local Postgres you own | none worth protecting |
| Exercise identity | `DROVI_FIREBASE_PROJECT_ID` | not a secret |
| Exercise generation (Phase 3) | `DROVI_GEMINI_API_KEY` | ✅ — use a **separate low-limit key**, never production's |

When you do need a value locally, put it in the **shell session**, not a file:

```bash
export DROVI_GEMINI_API_KEY=...      # this session only; gone when you close it
./gradlew bootRun
```

If a `.env` file is more convenient, `.env` and `.env.*` are gitignored (`.env.example` is
the only one tracked) — but it is a file on disk that survives a reboot, so prefer the
shell for anything genuinely secret.

⚠️ **Do not point local development at the production database.** A local process
connecting with production credentials can drop a table as easily as read one, and the
credential is then in your shell history, your IDE run configuration, and any crash dump.

---

## Rotation

INVARIANT: every secret must be rotatable **without downtime**. The pattern is always the
same — *publish new alongside old → switch → revoke old.*

| Secret | How |
| --- | --- |
| `DROVI_GEMINI_API_KEY` | Google AI Studio → create a second key → update Render → save (restarts) → verify a generation → revoke the old key |
| `DROVI_DB_PASSWORD` | Supabase → Settings → Database → Reset password → update Render → save. **Brief downtime** — Supabase free has one database user, so old and new cannot coexist. Accepted risk, recorded in `platform-security.md` |
| A project API key (a user's) | the user issues a second key, switches their client, revokes the first. `project_api_key` allows several live keys per project precisely for this |
| `DROVI_FIREBASE_PROJECT_ID` | not a secret; changing it means moving Firebase projects, not rotating |

## If a secret leaks

**Rotate first. Investigate second.** In that order, always.

1. Rotate the credential — immediately, before you understand the scope.
2. Then work out what it could reach and what it did.
3. Purging git history is **cleanup, never remediation**. A secret that was pushed is
   compromised regardless of what the history looks like afterwards.

## What we gave up, and when to revisit

Switch to a real vault when any of these becomes true — they are the reasons a vault earns
its keep, and none apply yet:

- **A second person** needs production access (sharing a Render login is not access control)
- **A second environment** appears — staging plus production means the same secret pasted twice
- **Audit matters** — you need to answer *who read this, and when*
- **Automated rotation** is required rather than a manual runbook
- A **compliance requirement** demands it

Until then the cost of a vault is a new bootstrap credential, a new free tier to stay
inside, and a new failure mode between the app and its configuration.
