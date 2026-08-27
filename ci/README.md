# CI definitions

Workflows are **authored here and copied** into the repo they build. GitHub only runs a
workflow from `.github/workflows/` on the repo's own default branch, so a workflow cannot
live in `dev-ops` and act on `cellbreak`.

| File | Copy to | Runs |
| --- | --- | --- |
| `ci.yml` | `cellbreak/.github/workflows/ci.yml` | every PR and push to `dev` or `main` |
| `deploy.yml` | `cellbreak/.github/workflows/deploy.yml` | push to `main`, or by hand |

Editing one here does nothing until it is copied. Change both, in the same change.

## Two names that must not drift

- **The CI job is called `ci`.** That exact string is what branch protection requires as a
  status check.
- **The PR-guard job is called `release-prs-come-from-dev`.** Same reason, in
  `.github/workflows/pr-guard.yml` on this repo's own project branch.

A check cannot be marked *required* until it has run at least once, so protection is
configured in two passes — see [../docs/github-setup.md](../docs/github-setup.md).

## Deliberately absent

| Thing | Why |
| --- | --- |
| A lint workflow | TypeScript with `strict` plus `noUncheckedIndexedAccess` is the linter here. A second tool would repeat it |
| A preview-deploy workflow | there is one environment on purpose — [../docs/deployment.md](../docs/deployment.md) |
| A browser test in CI | `apps/web/test/online-check.mjs` needs Chrome and a running Worker. It is a pre-deploy check by hand, not a gate — running it in CI would make the pipeline the flakiest thing in the project |
