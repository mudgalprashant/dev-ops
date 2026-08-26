# dev-ops — `bidceleb`

**Environment/config contract, CI/CD definitions, and operational docs for bidceleb.**
This is a shared repo with one long-lived branch per project; you are on the `bidceleb`
line.

| | |
| --- | --- |
| Release branch | `bidceleb` |
| Integration branch | `bidceleb-dev` |
| Work branches | `feat/<slice>`, `fix/<name>` off `bidceleb-dev` |
| Product repos | `bidceleb-backend`, `bidceleb-frontend` (release `main`, integration `dev`) |
| Context | `global-context`, branch `bidceleb` |

⚠️ **Never merge this branch into `main`.** `main` is what the *next* project branches
from; one bidceleb-specific variable landing there and every future project inherits it.
Generic improvements are written on `main` and picked up with `git merge main`. The
`pr-guard` workflow on `main` enforces this.

## What bidceleb is

A public board where anyone pays in US dollars to raise a celebrity's **popularity**. Each
payment is a **boost**, worth exactly the dollars paid; popularity is the cumulative sum of
settled boosts. Tabs (`ALL`, then categories, then subcategory subtabs) each show the single
figure that would place any celebrity at #1 in that tab:

```
increment    = max(min_increment, min(ceil(top × 5%), $50))
outbidTarget = top + increment
```

## What is different about this project, operationally

Three things drive every doc on this branch:

1. **The money risk runs inward, not outward.** Nothing here calls a metered API, so there
   is no runaway-spend problem. The risks are *money taken without popularity moving* and
   *popularity minted without payment* — both silent, neither returning a 500.
2. **`BIDCELEB_PAYMENT_WEBHOOK_SECRET` is the top-tier credential**, above the database
   password. It is the only thing standing between an attacker and unlimited free
   popularity, and the fraud leaves no trace at the payment provider.
3. **Traffic is spiky and read-heavy.** The growth loop is someone losing their position
   and posting about it, so bursts arrive after quiet periods — which makes the cold-start
   keep-alive load-bearing rather than hygienic.

## What lives here

| Path | What |
| --- | --- |
| `.env.example` | The full env-var contract — **names only, never values** |
| `docs/env-matrix.md` | Every `BIDCELEB_*` variable: which env, secret or not, how to verify |
| `docs/secrets.md` | The top-tier credential, classification, rotation |
| `docs/observability.md` | **The four silent failures**, the signals, the `alert.*` lines |
| `docs/runbook.md` | One procedure per silent failure |
| `docs/free-tier-budget.md` | What runs out first, for this traffic shape |
| `docs/HUMAN-SETUP-CHECKLIST.md` | **Everything the human must do by hand**, ordered |
| `ci/*.yml` | GitHub Actions, authored here and **copied** into the repo they build |

Inherited unchanged from `main` and canonical there: `docs/branching-strategy.md`,
`docs/github-setup.md`, `docs/NEW-PROJECT.md`, `docs/deployment.md`, `docs/free-stack.md`.
Do not fork one of those to change a project detail — if it needs a project detail, it was
the wrong file.

## What does NOT live here

Application code, and the app repos' own docs. Canonical cross-repo **decisions** live in
`global-context`, branch `bidceleb`, `shared/decisions.md`.

## Current state, honestly

| Thing | State |
| --- | --- |
| Backend code | **None.** Repo is empty |
| Frontend code | **None.** Repo is empty |
| Deployed environments | **None** |
| Supabase / Firebase projects | Do not exist — human tasks |
| Payment provider | **Undecided** — an open decision; the account is the long-lead item |
