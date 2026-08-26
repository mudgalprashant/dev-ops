# dev-ops — `main`

**Environment/config contract, CI/CD definitions, and operational docs.** This is a shared
repo: it carries **one long-lived branch per project**, plus this `main` branch for content
that is true regardless of project.

> **You are on `main`. Nothing project-specific belongs here.** Project work happens on
> that project's branch, and is never merged back. See
> [docs/branching-strategy.md](docs/branching-strategy.md).

## Branches

| Branch | Project | Repos covered |
| --- | --- | --- |
| `main` | — | the baseline every project branches from |
| `drovi` / `drovi-dev` | Drovi — AI-generated API sandboxes | `drovi-backend`, `drovi-frontend` |
| `bidceleb` / `bidceleb-dev` | bidceleb — pay-to-rank celebrity popularity board | `bidceleb-backend`, `bidceleb-frontend` |

**Starting a new project? → [docs/NEW-PROJECT.md](docs/NEW-PROJECT.md).** Read it before
creating any branch; step 1 is the one that gets skipped, and skipping it is unrecoverable
without a rewrite.

## What lives here

| Path | What |
| --- | --- |
| `docs/branching-strategy.md` | **Canonical branch model across all repos** |
| `docs/NEW-PROJECT.md` | How to add a project to the shared repos, and the completion gate |
| `docs/github-setup.md` | Making the rules real: visibility, default branch, protection |
| `docs/secrets.md` | **Where secrets live, how to set them, how to rotate them** |
| `docs/env-matrix.md` | The env-var contract: naming, classification, the pooler traps |
| `docs/deployment.md` | How a build reaches production, and why there is no staging |
| `docs/runbook.md` | The shape of a good procedure, plus the universal incidents |
| `docs/observability.md` | How to work out what fails *silently* in a given product |
| `docs/free-stack.md` | What we use for each concern, and what is ruled out |
| `docs/free-tier-budget.md` | How to work out what runs out first |
| `docs/HUMAN-SETUP-CHECKLIST.md` | The shape of the by-hand setup list |
| `ci/*.yml` | GitHub Actions, authored here and **copied** into the repo they build |
| `.env.example` | The env-var contract — **names only, never values** |

## What does NOT live here

Application code, and the app repos' own docs. Canonical cross-repo *decisions* live in
`global-context`, on the project's branch, in `shared/decisions.md`.

## Deliberately absent

| Thing | Why |
| --- | --- |
| A local Docker stack (`docker-compose.yml`, `make up`) | the test suite starts its own database. A `make up` that boots an unused service is a trap, not a reference |
| An SSH/systemd deploy workflow | the `Dockerfile` plus the host's build-from-repo is the one deploy path. Two contradictory paths in one repo is how a deploy goes to the wrong place |
| Anything project-specific | that is what the project branches are for |
