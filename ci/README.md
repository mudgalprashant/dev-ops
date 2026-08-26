# CI/CD workflows — authored here, placed in the app repos

`dev-ops` **owns** CI/CD, but GitHub Actions workflows must physically live inside the repo
they build. So these files are authored and version-controlled here (one source of truth)
and **copied** into each app repo under `.github/workflows/`.

| Source (this repo) | Destination | Owner repo |
| --- | --- | --- |
| `ci/backend-ci.yml` | `bidceleb-backend/.github/workflows/ci.yml` | bidceleb-backend |
| `ci/frontend-ci.yml` | `bidceleb-frontend/.github/workflows/ci.yml` | bidceleb-frontend |

Copy command, run from the **destination** repo, on branch `dev`:

```bash
mkdir -p .github/workflows
cp ../dev-ops/ci/backend-ci.yml .github/workflows/ci.yml
```

⚠️ **Do not write into a repo another person or agent is actively editing without saying
so first.** Coordinate the placement, then copy. Two people editing one workflow in two
repos is how a pipeline silently stops matching its source of truth.

⚠️ **Edited in one place only.** If a workflow is changed in the app repo, port the change
back here in the same session or the two diverge — and the copy in the app repo is the one
that runs, so `dev-ops` becomes confidently wrong.

## What each pipeline does

- **backend-ci** — JDK (Temurin) + Gradle wrapper → `./gradlew build` (unit, slice and
  integration tests) → migrations-apply-on-empty-DB check → format check → test-report
  artifact. **No repo secrets required**: the test suite starts a real database binary that
  arrives as a build dependency.
- **frontend-ci** — `npm ci` → lint → typecheck → test → build. Each step is tolerant of a
  script that does not exist yet, so a docs-only push stays green before the app has code.

## Deploy workflows

There is deliberately **no deploy workflow here.** The host builds from the repo itself on
a push to the release branch (see [../docs/deployment.md](../docs/deployment.md)), so a
deploy needs no CI job and no CI secret.

⚠️ A previous version of this repo carried an SSH-to-systemd deploy workflow *and* a
deployment doc describing a build-from-repo host. Two contradictory deploy paths in one
repo is how a release goes somewhere nobody expected. If a project genuinely needs a push
deploy, add it on that project's branch and correct `deployment.md` in the same change.

## Secrets these workflows need

**None.** Design it to stay that way: a test suite that needs a secret cannot run on a
fork's pull request. If a workflow ever does need one, it goes in a GitHub **Environment**
named `production` with required reviewers — never a repository secret, which any workflow
including one added by a fork's PR can read. See [../docs/secrets.md](../docs/secrets.md).

Branch policy: everything lands on the integration branch via PR + green CI; the release
branch receives only the release PR.
