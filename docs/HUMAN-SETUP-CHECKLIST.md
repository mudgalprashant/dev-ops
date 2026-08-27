---
title: Human setup checklist — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Human setup checklist

**Everything a person must do by hand.** Agents cannot create accounts, provision hosts, or
invent secret values.

**Nothing here blocks building or playing the game.** Local pass-and-play and online rooms
both run entirely on your machine via `wrangler dev`.

**Item 1 alone gets you a live URL.** A first deploy by hand needs only a Cloudflare
account — `wrangler login` authenticates through the browser, and no API token is involved:

```bash
cd apps/server && pnpm exec wrangler login
cd ../.. && pnpm --filter @cellbreak/web build
cd apps/server && pnpm exec wrangler deploy
```

Items 2–3 exist so **CI** can deploy without a human at a browser. Do them when you want
pushes to `main` to publish themselves, not before your first deploy.

Legend: **Feeds** = what it produces · **Verify** = how to know it worked · **Blocks** = what
stays broken until it is done.

---

## Before deploying

### 1. Cloudflare account
- **Why:** hosts the Worker, the Durable Objects and the client, all on the free plan.
- **Do:** [dash.cloudflare.com](https://dash.cloudflare.com) → Sign up. **No payment method
  is requested and none should be added.** Copy the **Account ID** from the right-hand side
  of the dashboard overview.
- **Feeds:** `CLOUDFLARE_ACCOUNT_ID`
- 📌 **The free plan covers everything this project uses**, Durable Objects included — they
  have been on the free plan since April 2025, SQLite-backed. Nothing needs upgrading.
- 📌 **Keeping a card off the account is the spend control.** Cloudflare suspends at the
  ceiling rather than billing, and with no card there is nothing to charge.
- **Verify:** `cd apps/server && pnpm exec wrangler login`, then `pnpm exec wrangler whoami`
  names your account.
- 📌 **The first deploy will offer to register a `*.workers.dev` subdomain.** Accept it —
  that is the free hostname the game is served on, with a managed certificate.
- **Blocks:** deploying, by hand or from CI.

### 2. Cloudflare API token
- **Why:** lets CI publish. It is the **only real secret in the project**.
- **Do:** Cloudflare → **My Profile → API Tokens → Create Token** → use the
  **"Edit Cloudflare Workers"** template → Continue → Create. **Copy it now; it is shown
  once.**
- **Feeds:** `CLOUDFLARE_API_TOKEN`
- ⚠️ **Use the template, not a Global API Key.** The template is scoped to Workers; the
  global key carries DNS and every zone setting on the account.
- ⚠️ **It never goes on a laptop.** Local development needs no token at all — `wrangler dev`
  runs Durable Objects locally. A token on a laptop ends up in a shell history or a backup.
- **Verify:** step 3's first deploy run reaches "Uploaded" rather than a 403.
- **Blocks:** deploying from CI.

### 3. GitHub repository secrets
- **Do:** `codecreeds/cellbreak` → **Settings → Secrets and variables → Actions** → add
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
- ⚠️ **This repo is under `codecreeds`, not `mudgalprashant`** like `dev-ops` and
  `global-context`. Two consequences: the Cloudflare token must belong to whoever owns the
  Cloudflare side, and `.github/CODEOWNERS` needs a handle with access to *this* org.
- **Verify:** the deploy workflow runs without warning that a secret is unset.
- **Blocks:** deploying.

---

## Worth doing early

### 4. Repository visibility
- **Decide:** public or private.
- 📌 **Public is recommended.** GitHub Actions is unlimited on public repos and capped at
  2,000 minutes a month on private ones. There is no secret in the source — the entire
  inventory is [secrets.md](secrets.md), and it is one CI token that lives in GitHub.
- **Blocks:** nothing, but it decides whether CI minutes are a budget line.

### 5. Branch protection
- **Why:** the branch model is convention until GitHub enforces it. A file cannot block a
  merge.
- **Do:** follow [github-setup.md](github-setup.md) for `cellbreak` `main` and `dev`.
- ⚠️ **Two traps, both documented there and both worth an afternoon:**
  - a status check cannot be marked *required* until it has **run once**, so protection is
    set in two passes;
  - while you are the only maintainer, **keep required approvals at 0**. GitHub forbids
    self-approval, and approvals ≥ 1 combined with "do not allow bypassing" locks you out
    of your own release branch with no way back.
- **Verify:** a direct push to `main` is rejected. Check it by trying, not by reading the
  checkboxes.
- **Blocks:** nothing mechanically; everything about keeping the model honest.

### 6. Local toolchain
- **Do:** Node 22+, then `corepack enable` (pnpm arrives with it). Then `pnpm install`.
- **Verify:** `pnpm test` → 29 passing.
- **Blocks:** all local work.

---

## After the first real game

### 7. Confirm the grid dimensions
`packages/engine/src/board.ts` holds every board size in one table. Whether "dense" feels
dense is a judgement only a person who has played it can make. Change the table; the tests
that assert cell counts will tell you what else to update.

---

## Deliberately not doing these

| Thing | Why not |
| --- | --- |
| A database | nothing outlives a room — [free-stack.md](free-stack.md) |
| An auth provider | a nickname and a room code |
| An uptime monitor | its job elsewhere is keeping a free service awake. Nothing here sleeps and nothing pauses after 7 idle days |
| A custom domain | `*.workers.dev` is free and has a managed certificate |
| Error tracking | not until there is traffic worth tracking. [observability.md](observability.md) names what to add first, and why |
| A staging environment | one environment on purpose — [deployment.md](deployment.md) |

---

## Completion gate

- [ ] Cloudflare account exists, **no card on it**, Account ID copied
- [ ] API token created from the **Workers template**, stored only in GitHub
- [ ] Both secrets set on `codecreeds/cellbreak`
- [ ] `CODEOWNERS` names a handle with access to the `codecreeds` org
- [ ] Visibility decided
- [ ] Branch protection on `main` and `dev`, **verified by a rejected push**
- [ ] `pnpm test` green locally
- [ ] A deploy has succeeded and two browsers have played each other on the live URL

Anything you could not complete → say so; it is tracked as `UNKNOWN`, never guessed.
