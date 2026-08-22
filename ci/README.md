# CI/CD workflows — authored here, placed in the app repos

dev-ops **owns** CI/CD, but GitHub Actions workflows must physically live inside
the repo they build. So these files are authored and version-controlled here (one
source of truth) and **copied** into each app repo under `.github/workflows/`.

| Source (this repo)     | Destination                                   | Owner repo    |
| ---------------------- | --------------------------------------------- | ------------- |
| `ci/backend-ci.yml`    | `drovi-backend/.github/workflows/ci.yml`      | drovi-backend |
| `ci/frontend-ci.yml`   | `drovi-frontend/.github/workflows/ci.yml`     | drovi-frontend |
| `ci/backend-deploy.yml`| `drovi-backend/.github/workflows/deploy.yml`  | drovi-backend |

## Placement rule (do not silently overwrite another agent's repo)

These land in repos actively edited by **Hirdesh** (backend) and **Kaushik**
(frontend). Placement is coordinated via hive messages before the copy happens —
do not write into their `.github/` unprompted.

Copy command (run from the destination repo, on branch `dev`):

```bash
# backend
mkdir -p .github/workflows
cp ../dev-ops/ci/backend-ci.yml .github/workflows/ci.yml

# frontend
mkdir -p .github/workflows
cp ../dev-ops/ci/frontend-ci.yml .github/workflows/ci.yml
```

## What each pipeline does

- **backend-ci** — JDK 26 (Temurin) + Gradle wrapper → `./gradlew build` (unit +
  slice + Testcontainers integration tests) → Flyway-on-empty-DB check → test
  reports artifact. No repo secrets required (Testcontainers uses the runner's
  own Docker daemon).
- **frontend-ci** — not yet written. The console is Next.js (#41) but has no code; author
  this in Phase 4 (typecheck → lint → test → build)
  so doc-only pushes stay green. Once code lands: `npm ci` → lint → typecheck →

## Secrets these workflows need

- **Build/test (now):** none.
- **Deploy (Phase 2):** container registry creds + hosting creds (backend);
  The backend needs **no** deploy secret — Render builds from the repo itself. The human
  adds any others as GitHub
  repo secrets — see `docs/HUMAN-SETUP-CHECKLIST.md`.

Branch policy (from canonical decisions): everything lands on `dev` via PR + green
CI; `main` receives no merges; releases are tags cut from `dev`.
