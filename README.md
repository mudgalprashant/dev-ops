# dev-ops — Drovi infrastructure & developer operations

Home for the **environment/config contract, CI/CD definitions, and operational/setup
docs** for Drovi. Branch per project; this is the `drovi` branch.

**Drovi builds a working replica of somebody else's production API.** You name a product,
an agent researches it, and you get a base URL to paste over the real one. It was
repurposed on 2026-08-22 from an unrelated flight-alerts product, and all four repos were
history-reset on 2026-08-23 (decisions #31, #42). Nothing of that product survives here.

## What lives here

| Path | What |
| --- | --- |
| `.env.example` | The full env-var contract — **names only, never values** |
| `docs/env-matrix.md` | Every var: which app, which env, how to verify |
| `docs/secrets.md` | **Where secrets live, how to set them, how to rotate them** |
| `docs/free-stack.md` | What we use for each concern, and what it costs |
| `docs/free-tier-budget.md` | Quantified headroom — what runs out first |
| `docs/HUMAN-SETUP-CHECKLIST.md` | **Everything the human must do by hand**, ordered |
| `docs/deployment.md` | How the backend reaches Render |
| `docs/runbook.md` | Deploy, rollback, rotate a secret, incidents |
| `docs/observability.md` | Logs, metrics, alerts, and how to trace one sandbox call |
| `docs/branching-strategy.md` | **Canonical branch model across all repos** — never commit to `main` |
| `docs/github-setup.md` | Making the rules real: visibility, default branch, branch protection |
| `ci/backend-ci.yml`, `ci/backend-deploy.yml` | GitHub Actions, authored here |

The product roadmap is canonical in `drovi-backend/docs/00-overview/roadmap.md`.

## What does NOT live here

Application code, and the app repos' own docs.

## Deliberately absent

| Thing | Why |
| --- | --- |
| A local Docker stack (`docker-compose.yml`, `make up`) | Decision #14 dropped Docker for local dev and #13 dropped Redis. The backend's tests start a **real Postgres binary that arrives as a Gradle dependency** — nothing to install, nothing to start |
| An inbound-webhook doc | Drovi has **no inbound webhook**. Nothing external calls it except each sandbox's own users |
| `ci/frontend-ci.yml` | The console is Next.js (#41) but has no code yet. Author this in Phase 4 |

## Current state, honestly

| Thing | State |
| --- | --- |
| Backend code | Committed on `drovi-backend` `main`. Phase 0 complete; Phase 1 next |
| Deployed environments | **None.** `render.yaml` is ready; nothing has been deployed |
| Supabase project | Does not exist — human task |
| Firebase project | Does not exist — human task |
| Gemini API key | Not set — human task; generation cannot run without it |

Canonical cross-repo decisions: `global-context` branch `drovi`, `shared/decisions.md`.
