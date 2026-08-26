---
title: Human setup checklist — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend, dev-ops]
---

# Human setup checklist — bidceleb

**Everything a person must do by hand.** Agents cannot create accounts, provision hosts,
spend money, accept terms, or invent secret values.

> **Never paste a value into a doc, a commit, or a chat.** Production values go in the
> Render dashboard, CI values go in a GitHub **Environment**, and production credentials
> never land on a laptop.

**Feeds** = the variable this produces · **Verify** = how to confirm it worked ·
**Blocks** = what stays broken until it is done.

---

## Start this one today, whatever else you do

### 0. The payment provider account

**Why now:** it is the only item on this list with an **external approval step**. Everything
else takes minutes and depends only on you; this takes days and depends on somebody else.
It blocks Phase 4, but if you start it in Phase 4 you will wait in Phase 4.

The constraint is **cross-border USD collection from an Indian entity**, not the API. Two
shapes of answer:

| Option | What it means |
| --- | --- |
| **Stripe** | what outbid.lol itself uses; cleanest API and webhook story. Verify Indian onboarding for international collection before building against it |
| **A merchant of record** (Dodo, Paddle, Polar) | the MoR is the seller of record, handles global tax and pays out to an Indian entity. Trade-off: they vet what you sell, and a pay-to-rank novelty with no deliverable needs pre-approval |

⚠️ **Ask the provider explicitly about the product.** "Users pay to raise a public
popularity score for a named real person; nothing is delivered, nothing is won, payments
are non-refundable." Getting a yes in writing before you build is cheap. Getting a no after
launch is not.

**Do:** open the account → complete verification → get the **API key** and the **webhook
signing secret** → register the webhook endpoint at `<base>/api/v1/webhooks/payments/<provider>`.
**Feeds:** `BIDCELEB_PAYMENT_API_KEY`, `BIDCELEB_PAYMENT_WEBHOOK_SECRET`.
**Verify:** a test-mode checkout settles and a boost appears.
**Blocks:** every real payment. *Not* local development — the `STUB` adapter covers that.

---

## Do these first — they block all local work

### 1. Supabase — the database

**Why:** the system of record for the boost ledger, and remote for every environment, so
there is no local Postgres to install and no schema drift.

**Do:** supabase.com → New project, name it `bidceleb` → **save the database password it
shows you, it is displayed once** → pick the region nearest your users. Wait for
provisioning, then **Connect** (top bar) → **Session pooler**. Copy host, port, username;
the username carries the project ref (`postgres.<project-ref>`).

**Feeds:** `BIDCELEB_DB_URL`, `BIDCELEB_DB_USERNAME`, `BIDCELEB_DB_PASSWORD`.
⚠️ Take the **SESSION** pooler (5432), not direct and not transaction mode (6543) — the
three traps in `docs/env-matrix.md` on `main`.
⚠️ Supabase hands you a **libpq** URL; ours is **JDBC**. Prepend `jdbc:`, drop any embedded
`user:password@`, keep `?sslmode=require`.
⚠️ A free project pauses after 7 days of zero requests; the keep-alive (step 4b) is what
prevents that.
**Verify:** the deploy log shows Flyway applying `V1__baseline`.
**Blocks:** everything.

### 2. Firebase — optional sign-in

**Why:** identity is optional in this product — anyone can boost with just an email, and
signing in only claims boost history. Firebase still removes password hashing, token
rotation and session storage from scope entirely.

**Do:** console.firebase.google.com → Add project → name it `bidceleb` → **disable Google
Analytics** (Sentry covers this) → **Build → Authentication → Get started** → enable
**Google**, and **Email/Password** if you want it → **Project settings → General** → copy
the **Project ID** (not the project *name* — they differ once a name is taken, e.g.
`bidceleb-4f21`) → **do NOT generate a service-account key** → add a test user.

**Feeds:** `BIDCELEB_FIREBASE_PROJECT_ID` — and nothing else.
📌 The project id is **not a secret**.
⚠️ A **wrong** project id fails quietly: tokens are rejected as wrong-audience, which reads
as "my login is broken". Check it first when sign-in misbehaves.
**Verify:** `GET /api/v1/me` with a real ID token returns 200.
**Blocks:** sign-in, boost history and the moderation queue. **Not** the board, and **not**
boosting — those never needed an account.

---

## Do these before deploying

### 3. Render — the host

**Why:** chosen for its **billing model**, not its specs — no credit card, and hitting a
limit **suspends rather than charges**.

**Do:** render.com → **Sign up with GitHub** → **New → Blueprint** → pick `bidceleb-backend`
→ Render reads `render.yaml` and proposes the service → it prompts for each `sync: false`
secret; paste `BIDCELEB_DB_*`, `BIDCELEB_FIREBASE_PROJECT_ID`, `BIDCELEB_PAYMENT_*` →
**Apply**.

**Feeds:** `BIDCELEB_PUBLIC_BASE_URL` = `https://bidceleb-backend.onrender.com`.
**Verify:** `curl …/actuator/health` → `{"status":"UP"}`, and the deploy log shows the
migrations applying.
📌 512 MB / 0.1 CPU is tight. If it OOMs, the honest fix is Render's paid instance, not a
week of tuning.

### 4. Keep-alive — Supabase `pg_cron`

**Why:** prevents Render's 15-minute spin-down **and** Supabase's 7-day pause, in one job.
Load-bearing: this board is shared on social media, so traffic arrives in bursts after long
quiet periods — precisely the pattern a cold start ruins.

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'bidceleb-keepalive', '*/5 * * * *',
  $$ select net.http_get('https://bidceleb-backend.onrender.com/actuator/health') $$
);
```
**Verify:** `select * from cron.job_run_details order by start_time desc limit 5;`
📌 750 instance-hours against 744 in a 31-day month leaves ~6 hours for redeploys.

### 5. GitHub

**Do:** nothing for secrets — **no workflow needs one.** The tests start their own Postgres
and use the `STUB` payment adapter; Render builds from the repo. If that ever changes, the
value goes in **Settings → Environments → `production`** with required reviewers, never a
repository secret.

Then branch protection, per `docs/github-setup.md` on `main`:

| Repo | Default branch | Protect | Required check |
| --- | --- | --- | --- |
| `bidceleb-backend`, `bidceleb-frontend` | `dev` | `main` and `dev` | `ci` |
| `dev-ops` | (shared) | `bidceleb` | `release-prs-come-from-dev` |
| `global-context` | (private) | — none available — | — |

⚠️ **Two traps, both of which cost an afternoon:** a status check cannot be *required*
until it has *run once*, so protection is set in two passes; and while you are solo,
required approvals stay at **0** — GitHub forbids self-approval, and approvals ≥ 1 plus
"do not allow bypassing" locks you out of your own release branch with no way back.

**Verify:** a direct push to a release branch is rejected. Do not trust the checkboxes.

---

## Do these before real users

### 6. Monitoring

**Why:** every failure in this product is silent — money taken without popularity moving,
popularity minted without payment, the board disagreeing with the ledger. None of them
returns a 500. See `docs/observability.md`.

**Do:** UptimeRobot monitoring `https://bidceleb-backend.onrender.com/actuator/health`
every 5 minutes. A Sentry project (platform: Java). A **log-based alert on Render keyed on
`alert.`** — that one is what surfaces the four failures above, and it is the one most
likely to be skipped because the first two are easier.

**Verify:** stop the app; UptimeRobot emails within ~5 minutes.

### 7. Legal and policy pages

**Why:** this product charges real money to rank real named people. Two exposures are
genuine — right of publicity and defamation — and both are cheap to manage up front and
expensive afterwards.

**Do, before the first real payment:**
- **Terms** stating plainly: a boost buys nothing, is **non-refundable**, confers no rights,
  and nothing is won. No chance, no prize, no payout — this is deliberately not a wager.
- **A disclaimer**, visible on the board itself: bidceleb is **not affiliated with,
  endorsed by, or connected to** any person listed.
- **A takedown path** with a named contact and a stated response time. The procedure is in
  `docs/runbook.md`: status → `HIDDEN`, never a hard delete.
- **Image licensing**: every celebrity image comes from Wikimedia Commons with its licence
  and attribution stored beside it and rendered on the page. **No press photos.**
- **Privacy**, covering the payer email and the optional display name.

⚠️ **The $100 listing fee needs its own sentence**: what it buys (review, and listing if
approved), and that it is **refunded in full if the submission is rejected**. A fee that
looks non-refundable for a service that might not be delivered is a chargeback waiting to
happen, and processors read chargeback rates before they read terms.

---

## Deferred — deliberately not doing these yet

| Thing | Why not | When |
| --- | --- | --- |
| Kubernetes | nothing to orchestrate at one instance; the `Dockerfile` **is** the deploy path | more than one instance |
| Docker for local dev | the tests start a real Postgres binary as a build dependency | probably never |
| Redis | Firebase takes sessions; the leaderboard cache is in-process at one instance | more than one instance |
| A custom domain | `*.onrender.com` has a managed certificate and costs nothing | when the board needs a brand |
| A charity split | decision 7 — the ledger reserves `disbursement_rule` so this needs no migration | if and when it is switched on |

---

## Completion gate

- [ ] Payment provider approved **in writing for this product**, keys and webhook secret issued
- [ ] Supabase project exists; the **session pooler** URL is what you saved, in JDBC form
- [ ] Firebase project exists; `BIDCELEB_FIREBASE_PROJECT_ID` set; **no service-account key**
- [ ] `payment_provider_config.active = true` only **after** the key is set
- [ ] `app_config` pricing and limits set, and you know how to hit `payments.enabled = false`
- [ ] `https://bidceleb-backend.onrender.com/actuator/health` returns UP with migrations applied
- [ ] `pg_cron` keep-alive scheduled and its last runs succeeded
- [ ] CI green in both product repos
- [ ] Branch protection **verified by a rejected push**
- [ ] UptimeRobot live; Sentry receiving; the `alert.` log alert configured
- [ ] Terms, disclaimer, takedown contact and privacy pages published
- [ ] **A test boost settles end to end in the provider's test mode**, and a replay of the
      same webhook changes nothing

**Anything you could not complete — say so.** It is tracked as `UNKNOWN`, never guessed.
