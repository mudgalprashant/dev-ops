---
title: Secrets — where they live, how to set them, how to rotate them
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Secrets

## The rule

> **No secret value is ever written to a file in any repo, or to any file on a developer's
> machine that is not already gitignored and transient.**

Secrets live in exactly two places, both encrypted at rest and neither in git:

| Store | Holds | Who can read it |
| --- | --- | --- |
| **The host's environment settings** (Render → Environment) | everything production needs | you, in the host's dashboard |
| **GitHub → Environment `production`** | anything CI needs to deploy | workflows on protected branches, with required reviewers |

## Why no external vault

An external vault (Doppler, Infisical, HCP Vault) is deliberately not adopted at this size.
Record the reasoning as an ADR in the project's backend repo the first time someone asks.

The short version: a vault adds a moving part and a new bootstrap credential without
removing a real risk, because the host's environment is already encrypted secret storage.

### The bootstrap problem, and why we do not have one

Any vault needs a credential to read it, and that credential must live somewhere — so
"no secrets anywhere" is never achievable; you only choose *where the last one lives*.

With this model there is **no vault client and no vault token at all**. The application
reads ordinary environment variables the host injects into the container. The last
credential is your host login, protected by MFA, and it is never on disk.

## Not everything called "config" is a secret

Treating a non-secret as secret is its own cost: it ends up in one dashboard, undocumented,
and nobody can reproduce a local run.

Classify every variable in the project's `env-matrix.md` into exactly one of these:

| Class | Meaning | Handling |
| --- | --- | --- |
| ✅ **Secret** | possessing it lets someone spend money, read or alter data, or impersonate the system | host environment only; never on a laptop unless it is a separate low-limit credential |
| 🟡 **Sensitive** | not dangerous alone, but it names the target a secret unlocks | keep it beside the secret; do not publish it |
| ❌ **Config** | public or harmless; the system's behaviour, not its keys | check the *name* into `.env.example`, document it, stop worrying about it |

⚠️ **Each project must name its own top-tier credential** — the single value whose leak is
worst, and why. It goes at the top of that project's `secrets.md`. If nobody can name it,
nobody has thought about it.

⚠️ **Anything a browser receives is public.** A build-time prefix such as `NEXT_PUBLIC_`
does not protect a value; it publishes it. This is an invariant, not a caution.

---

## Step 1 — Production secrets, in the host's dashboard

1. Dashboard → your service → **Environment**.
2. **Add Environment Variable** for each row in `env-matrix.md` marked *Secret*.
3. **Save changes.** The service restarts; a restart is the only way a changed value takes
   effect.

`render.yaml` declares each one with `sync: false`, which means *"prompt me, never store
this in git."* That is why the repo can describe every variable without holding a value.

⚠️ **Never paste a secret into `render.yaml`, a commit message, a PR description, or a
chat.** Anything you paste is in a log somewhere.

## Step 2 — CI secrets, in a GitHub Environment

Only needed once a workflow has to reach something protected. Do it as a GitHub
**Environment**, never a repository secret.

1. Repo → **Settings → Environments → New environment** → name it `production`.
2. **Deployment protection rules** → tick **Required reviewers** → add yourself.
3. **Environment secrets → Add secret** for each one CI needs.
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

**Name deploy secrets after the role, not the vendor** — `DEPLOY_SSH_KEY`, not
`ACME_CLOUD_SSH_KEY`. Hosts get changed; a workflow that hardcodes a vendor name in its
secret names makes the next move a rename across three places instead of one value change.

## Step 3 — Local development

**The policy: production credentials never land on a laptop.**

Local development does not need them, and this is worth internalising because it removes
the whole class of "my machine got compromised" incidents. Build the test suite so it
needs **no credentials at all** — that is what makes this policy affordable rather than
aspirational.

When you do need a value locally, put it in the **shell session**, not a file:

```bash
export <PROJECT>_SOME_API_KEY=...      # this session only; gone when you close it
```

If a `.env` file is more convenient, `.env` and `.env.*` are gitignored (`.env.example` is
the only one tracked) — but it is a file on disk that survives a reboot, so prefer the
shell for anything genuinely secret. Where a third-party service offers **test-mode
credentials**, use those locally and never the live ones.

⚠️ **Do not point local development at the production database.** A local process
connecting with production credentials can drop a table as easily as read one, and the
credential is then in your shell history, your IDE run configuration, and any crash dump.

---

## Rotation

INVARIANT: every secret must be rotatable **without downtime**. The pattern is always the
same — *publish new alongside old → switch → revoke old.*

| Situation | Pattern |
| --- | --- |
| The provider allows several live credentials | create the second → update the host → save → verify → revoke the first. No downtime |
| The provider allows exactly one | resetting it is a brief outage. Record that in the project's `platform-security.md` as an accepted risk rather than discovering it during an incident |
| A credential the system issues to *users* | issue a second, let them switch, revoke the first. Design the schema to allow several live keys per holder precisely for this |

**Never rotate by editing a file in a repo.** A repo is not a secret store; the fact that a
value can be typed into one is exactly the problem.

## If a secret leaks

**Rotate first. Investigate second.** In that order, always.

1. Rotate the credential — immediately, before you understand the scope.
2. Then work out what it could reach and what it did.
3. Purging git history is **cleanup, never remediation**. A secret that was pushed is
   compromised regardless of what the history looks like afterwards.

## What we gave up, and when to revisit

Switch to a real vault when any of these becomes true — they are the reasons a vault earns
its keep:

- **A second person** needs production access (sharing a host login is not access control)
- **A second environment** appears — staging plus production means the same secret pasted twice
- **Audit matters** — you need to answer *who read this, and when*
- **Automated rotation** is required rather than a manual runbook
- A **compliance requirement** demands it

Until then the cost of a vault is a new bootstrap credential, a new free tier to stay
inside, and a new failure mode between the app and its configuration.
