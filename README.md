# dev-ops — Cellbreak infrastructure & developer operations

Environment contract, CI/CD definitions, and operational docs for **Cellbreak**. This is
the `cellbreak` branch of a shared repo — it is the **release line** for this project, and
`cellbreak-dev` is its integration branch.

> ⚠️ **Never commit to `cellbreak` and never open a PR into it except the release PR from
> `cellbreak-dev`.** In this repo `cellbreak` plays the role `main` plays in a product repo.
> See [docs/branching-strategy.md](docs/branching-strategy.md).

**Cellbreak is Chain Reaction for the browser** — the Android game's rules and physics on a
flat 2D grid. 2–8 players, three grid shapes in two densities, local pass-and-play, and
online rooms with a code and an invite link. Code lives in `codecreeds/cellbreak`.

## The short version of the stack

Everything is Cloudflare, on the free plan, with **no card on the account**. One Worker
serves the client *and* the WebSocket API; one Durable Object per room holds the game.
**There is no database, no auth provider and no second service** — which is why this
directory is small. See [docs/free-stack.md](docs/free-stack.md).

## What lives here

| Path | What |
| --- | --- |
| `docs/HUMAN-SETUP-CHECKLIST.md` | **Everything a person must do by hand**, ordered. Start here |
| `docs/free-stack.md` | What is used for each concern, and what Render/Supabase/Firebase were ruled out for |
| `docs/free-tier-budget.md` | What runs out first — and why the real limit is not in the table |
| `docs/observability.md` | **The seven ways this game fails silently** |
| `docs/runbook.md` | One procedure per silent failure, plus deploy and rollback |
| `docs/deployment.md` | One artefact, one origin, and the build step that is load-bearing |
| `docs/secrets.md` | The inventory: one CI token |
| `docs/env-matrix.md` | The runtime contract — which is empty, on purpose |
| `docs/branching-strategy.md` | Canonical branch model |
| `docs/github-setup.md` | Turning the conventions into enforcement |
| `ci/*.yml` | GitHub Actions, authored here and **copied** into the product repo |
| `.env.example` | Names only, never values — and here, none |
| `Makefile` | `make serve`, `make deploy`, `make tail` |

## Current state, honestly

| Thing | State |
| --- | --- |
| Engine, client, Worker | written and tested — 29 engine tests, plus two integration checks |
| Local play | working, all six shape × size boards |
| Online play | working locally; two-tab check passes end to end |
| Cloudflare account | **does not exist — human task #1** |
| Deployed | **never.** Nothing has been published |
| Branch protection | not configured |

Canonical cross-repo decisions: `global-context`, branch `cellbreak`, `shared/decisions.md`.

## What does NOT live here

Application code, and the product repo's own docs.

## Deliberately absent

| Thing | Why |
| --- | --- |
| A Docker stack | there is nothing to run but `wrangler dev`, which starts the Worker, the Durable Objects and the client in one command |
| A database runbook | there is no database |
| A staging environment | one environment on purpose — [docs/deployment.md](docs/deployment.md) |
| An uptime monitor | nothing sleeps and nothing pauses |
