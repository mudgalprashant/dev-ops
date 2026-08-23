---
title: Human setup checklist — Drovi
status: current
last_updated: 2026-08-22
---

# Human setup checklist

**Everything a person must do by hand.** Agents cannot create accounts, provision hosts,
spend money, or invent secret values.

Never paste a value into a doc, a commit, or a chat. Values go in `.env` locally, or the
platform / GitHub secret store for hosted.

Legend: **Feeds** = the env var this produces · **Verify** = how to confirm it worked ·
**Blocks** = what stays broken until it is done.

Var reference: [env-matrix.md](./env-matrix.md) · Stack rationale: [free-stack.md](./free-stack.md)

---

## Do these first (they block all local work)

### 1. Supabase — the database
- **Why:** the system of record, remote for every environment including local. No
  local Postgres to install and no schema drift between machines.
- **Do:**
  1. supabase.com → **New project**. Name it `drovi`. **Save the database password
     it shows you — it is displayed once.** Pick the region nearest your users.
  2. Wait for provisioning, then **Connect** (top bar) → **Session pooler**.
  3. Copy the host, port and username from there. The username carries the project
     ref: `postgres.<project-ref>`.
- **Feeds:** `DROVI_DB_URL`, `DROVI_DB_USERNAME`, `DROVI_DB_PASSWORD`
- ⚠️ **Take the SESSION pooler (port 5432), not the direct connection and not
  transaction mode (6543).** All three appear in that dialog and only one works:
  - **Direct** is IPv6-only unless you buy the IPv4 add-on. Northflank has no IPv6
    egress, so this fails to connect and the error reads like a firewall problem.
  - **Transaction mode (6543)** does not support prepared statements. Hibernate and
    Flyway both use them, and Flyway's migration lock is connection-scoped, so
    migrations can deadlock or half-apply.
- ⚠️ **A free project pauses after 7 days with zero requests**, which stops
  everything silently. Our own sweep jobs keep it awake; the uptime monitor in
  step 9 is the backstop.
- **Verify:** paste the URL into the Supabase SQL editor's connection test, or once
  the app deploys, watch the logs for Flyway applying `V1__baseline`.
- **Blocks:** every backend slice past the current skeleton.

### 2. Firebase project — authentication
- **Why:** Firebase owns identity. It replaces our own registration, login, password
  hashing, refresh-token rotation and session storage.
- **Do:**
  1. console.firebase.google.com → **Add project** → name it `drovi`. Disable Google
     Analytics (we use Sentry).
  2. **Build → Authentication → Get started.** Enable **Email/Password**. Enable **Google**
     if you want social sign-in.
  3. **Project settings → Service accounts → Generate new private key.** This downloads a
     JSON file. **This file is a full admin credential — it is not a config file.** Save it
     outside the repo. `.gitignore` already blocks `firebase-adminsdk-*.json`, but do not
     rely on that.
  4. **Project settings → General → Your apps → Add app → Web** (the app registers itself
     later). Copy the config values shown.
- **Feeds:** backend `DROVI_FIREBASE_PROJECT_ID` — **and nothing else.**
- 📌 **You do NOT need a service-account key.** Verifying an ID token needs only the project
  id, because the token is an RS256 JWT signed with keys Google publishes (ADR-0006). Skip
  any step that tells you to download `firebase-adminsdk-*.json`; there is nothing here to
  keep secret.
- 📌 The project id is on the Firebase console's **Project settings** page, and is the same
  string the console's publishable web config uses.
- **Verify:** with `DROVI_FIREBASE_PROJECT_ID` set, `GET /api/v1/me` with a real ID token
  returns 200 and provisions an account. Without it, every console route returns 503
  `AUTH_NOT_CONFIGURED` — which is the correct fail-closed state, not a misconfiguration
- **Verify:** create a test user in the Firebase console → **Authentication → Users**.
- **Blocks:** every authenticated endpoint, so effectively everything.

---

## Do these before the generation slice

### 3. Anthropic — the model provider

Generation is the product's headline feature and it cannot run without this.

1. Create an API key at <https://console.anthropic.com/> → **API keys**.
2. Set it as `DROVI_ANTHROPIC_API_KEY` — locally in `.env`, on Render in the dashboard.
   It is **never** stored in the database; `ai_provider_config.api_key_env_var` records
   only the *name* of the variable, so a database backup is never a credential leak.
3. Only then activate the provider:

   ```sql
   UPDATE ai_provider_config SET active = true WHERE code = 'ANTHROPIC';
   ```

   ⚠️ Do this **after** the key is set, not before. A provider marked active with no key
   fails every call at request time instead of failing at startup — the worse failure.

4. Set your ceilings before generating anything. These are database rows, not env vars,
   so you can change them mid-incident without a deploy:

   ```sql
   UPDATE app_config SET value = '5000000' WHERE key = 'ai.daily.cost.cap.micros';
   -- micro-USD: 5000000 = $5/day, platform-wide
   ```

   The kill switch is `UPDATE app_config SET value='false' WHERE key='ai.enabled';` —
   it stops *spending*, never *serving*. Existing sandboxes keep answering.

5. **Decide the model routing.** All six purposes currently route to `claude-opus-5`.
   `ai.model.SEED` is the highest-volume purpose and the obvious first candidate to move
   to a cheaper model. That is a cost/quality call only you can make.


## Do these before deploying

### 4. Render — the host
- **Why:** chosen for its **billing model**, not its specs. No credit card at all,
  and hitting a limit **suspends the service rather than charging you** — which is
  the property that ruled out GCP, Oracle and every other card-based host.
- **Do:**
  1. render.com → **Sign up with GitHub**. No payment method is requested.
  2. **New → Blueprint** → pick the `drovi-backend` repo. Render reads
     `render.yaml` and proposes the service — no dashboard configuration to get
     wrong.
  3. It will prompt for each `sync: false` secret. Paste the values from your
     `.env` (`DROVI_DB_*`, `DROVI_FIREBASE_*`, `DROVI_ANTHROPIC_API_KEY`).
  4. **Apply.** The first build takes a while — it compiles the jar inside the
     image on a small instance.
- **Feeds:** `DROVI_PUBLIC_BASE_URL` — the assigned `https://drovi-backend.onrender.com`
- **Verify:** `curl https://drovi-backend.onrender.com/actuator/health` →
  `{"status":"UP"}`, and the deploy log shows Flyway applying V1 and V2.
- 📌 **Free instances spin down after 15 minutes idle**, and a cold start takes
  30–60 s. That matters more now than it used to: a sandbox is called by someone
  else's *running application*, which will see a 30-second first request as a
  timeout, not as a cold start. Step 4b keeps the instance awake, which makes it
  load-bearing rather than a nicety.
- 📌 **512 MB and 0.1 CPU is genuinely tight for a JVM.** The image caps the heap
  at 65% and disables the C2 compiler. If it OOMs, the options are Render's $7
  instance, a card-based host with a budget alert, or a TypeScript rewrite —
  and because deployment is a Dockerfile, the first two are a config change.

### 4b. Keep-alive — Supabase `pg_cron`
- **Why:** it prevents Render's 15-minute idle spin-down, and it keeps the Supabase
  project from pausing after 7 days of zero requests. 750 instance-hours/month against
  744 hours in a long month, so staying awake fits the documented allowance.
- **Do:** Supabase dashboard → **SQL Editor**, then:
  ```sql
  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  select cron.schedule(
    'drovi-keepalive', '*/5 * * * *',
    $$ select net.http_get('https://drovi-backend.onrender.com/actuator/health') $$
  );
  ```
- **Verify:** `select * from cron.job_run_details order by start_time desc limit 5;`
  shows succeeded runs, and the Render service stops reporting a cold start.

### 5. GitHub repo secrets
- **Do:** each repo → **Settings → Secrets and variables → Actions**.
  - `drovi-backend`: **none needed for deploy** — Render builds from the repo itself, and
    every secret lives in the Render dashboard, not in GitHub. Add `SENTRY_DSN` only when
    error tracking is wired.
  - `drovi-frontend`: none — the repo has no code and no chosen stack (decision I).
- **Verify:** a CI run referencing a secret does not warn that it is unset.

### 6. Branch protection
- **Why:** the branching strategy and `CODEOWNERS` only *suggest* until GitHub enforces
  them. A file cannot block a merge.
- **Do:** `drovi-backend` and `drovi-frontend` → **Settings → Branches → Add ruleset** on
  `dev` **and** `main`: require a PR, require review from Code Owners, require status
  check **`ci`**.
- **Verify:** a trivial PR touching a CODEOWNERS path cannot merge without approval + green CI.

### 7. Monitoring — not optional
- **Why:** every failure in this product is **silent**. See [free-stack](./free-stack.md).
- **Do:** create a free **UptimeRobot** account; monitor `https://drovi-backend.onrender.com/actuator/health`
  every 5 minutes. Create a free **Sentry** project (platform: Java) and copy the DSN.
- **Feeds:** `SENTRY_DSN`
- **Verify:** stop the app; UptimeRobot emails you within ~5 minutes.

---

## Deferred — deliberately not doing these yet

| Thing | Why not | When |
| --- | --- | --- |
| Kubernetes | Nothing to orchestrate at one instance. The `Dockerfile` **is** the deploy path — Render builds it from `main` | When we run more than one instance |
| Docker for local dev | Tests run a real Postgres binary as a Gradle dependency. Nothing to install, nothing to start | Probably never |
| Redis | Firebase takes sessions; cache is in-process at one instance | If we run more than one instance |
| A custom domain | `*.onrender.com` has a managed certificate and costs nothing | When the console needs a brand |

---

## Completion gate

- [ ] Supabase project exists; the **session pooler** URL is what you saved
- [ ] Firebase project exists; `DROVI_FIREBASE_PROJECT_ID` set (no service-account key needed)
- [ ] `DROVI_ANTHROPIC_API_KEY` set, and **only then** `ai_provider_config.active = true`
- [ ] Spend caps set in `app_config`, and you know how to hit the kill switch
- [ ] `https://<service>.onrender.com/actuator/health` returns UP, with 2 migrations applied
- [ ] `pg_cron` keep-alive scheduled and succeeding
- [ ] GitHub secrets set; CI green
- [ ] Branch protection on `main`
- [ ] UptimeRobot monitor live; Sentry receiving events
- [ ] **The backend is actually committed.** `drovi-backend` `main` HEAD is still
      `Initial commit`; nothing can deploy until that changes

Anything you could not complete → say so; it is tracked as `UNKNOWN`, never guessed.
