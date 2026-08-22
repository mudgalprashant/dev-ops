---
title: Branching strategy
status: current
last_updated: 2026-08-23
applies_to: [drovi-backend, drovi-frontend, dev-ops, global-context]
authority: this file is canonical; other repos link here rather than restate it
---

# Branching strategy

## The rules, in one place

1. **Never commit directly to `main`.** Not a fix, not a typo, not a "quick" revert.
2. **Never open a PR into `main` except the release PR from `dev`.**
3. **All work happens on `feat/<feature-name>` or `fix/<fix-name>`, branched from `dev`.**
4. **PRs are raised into `dev`.**
5. **When `dev` is live and stable, one PR is raised `dev` → `main`, and the human decides
   the merge.** No agent merges to `main`, ever.

Everything below is detail.

---

## Product repos — `drovi-backend`, `drovi-frontend`

```
main                     release. protected. the human alone merges here.
 └── dev                 integration. everything lands here via PR + green CI.
      ├── feat/<name>    one vertical slice, short-lived
      └── fix/<name>     one defect, short-lived
```

### Flow

```bash
git checkout dev && git pull
git checkout -b feat/sandbox-generation
# …work, commit…
git push -u origin feat/sandbox-generation
# open a PR into dev
```

### Rules

| Rule | Why |
| --- | --- |
| Branch off `dev`, PR into `dev`, squash-merge, delete the branch | Keeps `dev` history one line per slice, so `git log --oneline` reads as a changelog |
| Never commit directly to `dev` or `main` | CI is the gate; a direct push skips it |
| `dev` → `main` is a **release PR**, opened only when `dev` is genuinely live and stable. Merge commit, then tag `v0.x.y` | `main` answers "what is running in production", and nothing else |
| **Only the human merges `dev` → `main`** | It is a release decision, not an engineering one |
| A branch name states the *slice*, not the file — `feat/sandbox-generation`, not `feat/add-entity` | A slice that cannot be named in three words is too big |
| Rebase on `dev` before opening the PR; never rebase after review starts | Reviewers lose their place when history moves under them |
| A hotfix is still `fix/<name>` off `dev` | If `dev` is too unstable to release from, that is the problem to fix — not a reason to bypass it |

---

## Shared repos — `dev-ops`, `global-context`

These serve **other projects too**, so they carry one long-lived branch per project.
Drovi content must never reach a branch another project reads.

```
dev-ops
 ├── drovi              release line for the drovi project  ← plays main's role
 │    └── dev           integration for drovi
 │         ├── feat/<name>
 │         └── fix/<name>
 └── <other-project>    same shape

global-context
 └── drovi              the drovi project's context (see the exception below)
```

### The mapping, stated explicitly

In `dev-ops`, **`drovi` is the release branch** — it plays exactly the role `main` plays in
a product repo. `dev` is its integration branch. So the five rules read:

| Product repo | `dev-ops` |
| --- | --- |
| `main` | `drovi` |
| `dev` | `dev` |
| `feat/…`, `fix/…` | same |

⚠️ **Revisit this when a second project lands in `dev-ops`.** A single unqualified `dev`
branch is unambiguous only while `drovi` is the only project. The second project needs
`<project>-dev`, or `dev` needs renaming to `drovi-dev` at that point.

### `global-context` is deliberately excluded

`global-context` has **no `dev` branch**. Its content is compressed context that must be
correct *the moment* the code it describes lands — a staging branch would let context and
code drift, which is the exact failure that repo exists to prevent. Context changes are
committed to `drovi` alongside the change they describe.

It is also **private**, so branch protection is unavailable on the free plan. Its `drovi`
branch is therefore unprotected — an accepted gap, not an oversight. See
[github-setup.md](github-setup.md) Step 5.

### Merges go one way

```
main ──────────────▶ drovi          ALLOWED  (pick up shared conventions)
drovi ─────────✗───▶ main           NEVER    (leaks drovi into other projects)
drovi ─────────✗───▶ <other>        NEVER
```

| Rule | Why |
| --- | --- |
| A project branch is **never** merged into `main` | `main` is what a *new* project branches from. One drovi-specific env var landing there and every future project inherits it |
| Content genuinely useful to every project is committed **to `main` directly**, then picked up with `git merge main` | If you find yourself wanting to merge upward, you wrote it on the wrong branch |
| A new project branches from `main`, never from a project branch | Same reason |
| Forward-merge `main` into a project branch whenever `main` moves | Otherwise project branches quietly drift off the shared baseline |

**Why one branch per project instead of one repo per project:** the shared content
(conventions, security baseline, glossary) is small and changes rarely, but must stay
identical everywhere. In separate repos it would be copy-pasted and diverge within a month.
On branches, `git merge main` keeps it honest and the divergence is visible in one command.

---

## Working across repos

A change spanning repos (a contract change, a new env var, a new secret) uses **the same
branch name in every repo it touches**, with the PRs cross-linked. Land them in this order,
because each depends on the one before:

1. `global-context` — the contract or decision, on `drovi`
2. `dev-ops` — env vars, CI, deployment, on `feat/<name>` → `dev`
3. `drovi-backend` — the server side, on `feat/<name>` → `dev`
4. `drovi-frontend` — the client side, on `feat/<name>` → `dev`

**The API contract is the interlock.** `global-context/shared/api-contract.md` is
authoritative. A change to either boundary updates it in the same change, or released
clients break silently.

---

## Branch protection

The rules above are convention until GitHub enforces them. **Step-by-step setup:
[github-setup.md](github-setup.md)** — visibility, default branch, protection rules, and
how to verify each control actually works.

Two things worth knowing before you read it:

- **GitHub cannot restrict who *opens* a PR**, only who merges. `.github/workflows/pr-guard.yml`
  is the substitute: as a required status check, it blocks any PR into the release branch
  that did not come from `dev`.
- **"Only I can merge" comes from not granting write access**, not from a checkbox. These
  are personal repos, so contributors fork — and a fork PR cannot be merged by its author.

⚠️ Until this is configured, nothing stops a direct push. Convention is not a control.

---

## Quick reference

```bash
# start a slice (product repo, or dev-ops)
git checkout dev && git pull && git checkout -b feat/<name>

# start a fix
git checkout dev && git pull && git checkout -b fix/<name>

# release: open a PR dev → main (or dev → drovi in dev-ops). The HUMAN merges it.

# shared repo — add something every project should have
git checkout main && <edit> && git commit && git checkout drovi && git merge main
```
