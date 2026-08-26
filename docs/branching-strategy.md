---
title: Branching strategy
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
authority: this file is canonical; other repos link here rather than restate it
---

# Branching strategy

This is the `main` branch of a **shared** repo. Everything here is true for every project.
Project-specific content lives on that project's own branch and must never be merged back.

## The rules, in one place

1. **Never commit directly to the release branch.** Not a fix, not a typo, not a "quick"
   revert.
2. **Never open a PR into the release branch except the release PR from the integration
   branch.**
3. **All work happens on `feat/<feature-name>` or `fix/<fix-name>`, branched from the
   integration branch.**
4. **PRs are raised into the integration branch.**
5. **When the integration branch is live and stable, one PR is raised into the release
   branch, and the human decides the merge.** No agent merges to a release branch, ever.

Everything below is detail.

---

## Product repos — `<project>-backend`, `<project>-frontend`

```
main                     release. protected. the human alone merges here.
 └── dev                 integration. everything lands here via PR + green CI.
      ├── feat/<name>    one vertical slice, short-lived
      └── fix/<name>     one defect, short-lived
```

A product repo belongs to exactly one project, so it needs no per-project branch and its
names are the plain ones: release is `main`, integration is `dev`.

### Flow

```bash
git checkout dev && git pull
git checkout -b feat/<slice-name>
# …work, commit…
git push -u origin feat/<slice-name>
# open a PR into dev
```

### Rules

| Rule | Why |
| --- | --- |
| Branch off `dev`, PR into `dev`, squash-merge, delete the branch | Keeps `dev` history one line per slice, so `git log --oneline` reads as a changelog |
| Never commit directly to `dev` or `main` | CI is the gate; a direct push skips it |
| `dev` → `main` is a **release PR**, opened only when `dev` is genuinely live and stable. Merge commit, then tag `v0.x.y` | `main` answers "what is running in production", and nothing else |
| **Only the human merges `dev` → `main`** | It is a release decision, not an engineering one |
| A branch name states the *slice*, not the file — `feat/celebrity-leaderboard`, not `feat/add-entity` | A slice that cannot be named in three words is too big |
| Rebase on `dev` before opening the PR; never rebase after review starts | Reviewers lose their place when history moves under them |
| A hotfix is still `fix/<name>` off `dev` | If `dev` is too unstable to release from, that is the problem to fix — not a reason to bypass it |

---

## Shared repos — `dev-ops`, `global-context`

These serve **every project**, so they carry **one long-lived branch per project**, plus
`main` for content that is true regardless of project. One project's content must never
reach a branch another project reads.

```
dev-ops
 ├── main                    project-agnostic baseline  ← new projects branch from here
 ├── <project>               release line for that project   ← plays main's role
 │    └── <project>-dev      integration for that project
 │         ├── feat/<name>
 │         └── fix/<name>
 └── <other-project>         same shape

global-context
 ├── main                    the protocol and the empty templates
 ├── <project>               that project's context (no dev branch, by design)
 └── <other-project>
```

### The mapping, stated explicitly

In `dev-ops`, **the branch named after the project is the release branch** — it plays
exactly the role `main` plays in a product repo:

| Product repo | `dev-ops` |
| --- | --- |
| `main` | `<project>` |
| `dev` | `<project>-dev` |
| `feat/…`, `fix/…` | same |

The integration branch is **qualified with the project name**. An unqualified `dev` is
unambiguous only while one project exists; the moment a second lands, `dev` no longer says
whose integration branch it is. Qualify it from the start.

### `global-context` is deliberately excluded

`global-context` has **no integration branch**. Its content is compressed context that must
be correct *the moment* the code it describes lands — a staging branch would let context
and code drift, which is the exact failure that repo exists to prevent. Context changes are
committed to the project branch alongside the change they describe.

It may also be **private**, in which case branch protection is unavailable on the free plan
and its project branches are unprotected — an accepted gap, not an oversight. See
[github-setup.md](github-setup.md) Step 5.

### Merges go one way

```
main ──────────────────▶ <project>          ALLOWED  (pick up shared conventions)
<project> ────────✗────▶ main               NEVER    (leaks one project into all others)
<project> ────────✗────▶ <other-project>    NEVER
```

| Rule | Why |
| --- | --- |
| A project branch is **never** merged into `main` | `main` is what a *new* project branches from. One project-specific env var landing there and every future project inherits it |
| Content genuinely useful to every project is committed **to `main` directly**, then picked up with `git merge main` | If you find yourself wanting to merge upward, you wrote it on the wrong branch |
| A new project branches from `main`, never from a project branch | Same reason. See [NEW-PROJECT.md](NEW-PROJECT.md) |
| Forward-merge `main` into a project branch whenever `main` moves | Otherwise project branches quietly drift off the shared baseline |
| If something on a project branch turns out to be generic, **rewrite it onto `main`** rather than cherry-picking | Cherry-picking carries the original project's framing with it. Generic content should read as generic |

⚠️ **`main` must share history with every project branch.** It is branched from the repo's
root commit, not created as an orphan. An orphan `main` makes `git merge main` fail with
*refusing to merge unrelated histories*, and the entire forward-merge mechanic above stops
working. If you are bootstrapping a shared repo that has no `main`, see
[NEW-PROJECT.md](NEW-PROJECT.md) §1.

**Why one branch per project instead of one repo per project:** the shared content
(conventions, security baseline, glossary) is small and changes rarely, but must stay
identical everywhere. In separate repos it would be copy-pasted and diverge within a month.
On branches, `git merge main` keeps it honest and the divergence is visible in one command.

---

## Working across repos

A change spanning repos (a contract change, a new env var, a new secret) uses **the same
branch name in every repo it touches**, with the PRs cross-linked. Land them in this order,
because each depends on the one before:

1. `global-context` — the contract or decision, on `<project>`
2. `dev-ops` — env vars, CI, deployment, on `feat/<name>` → `<project>-dev`
3. `<project>-backend` — the server side, on `feat/<name>` → `dev`
4. `<project>-frontend` — the client side, on `feat/<name>` → `dev`

**The API contract is the interlock.** `global-context/shared/api-contract.md` is
authoritative. A change to either side of a boundary updates it in the same change, or
released clients break silently.

---

## Commit conventions

Lowercase type prefix, lowercase sentence-style subject, no scope, no trailing period,
imperative, ≤72 characters.

```
ops: infrastructure and operations for <project>
docs: branch model — work on feat/ and fix/ off dev, never on main
ci: CODEOWNERS and a PR guard for the release branch
context: <what changed in the context and why>
```

`feat` and `fix` are branch prefixes; the commit types in use are `ops:`, `docs:`, `ci:`,
`feat:`, `fix:`, `context:`. Bodies explain *why*, not *what* — the diff already says what.

---

## Branch protection

The rules above are convention until GitHub enforces them. **Step-by-step setup:
[github-setup.md](github-setup.md)** — visibility, default branch, protection rules, and
how to verify each control actually works.

Two things worth knowing before you read it:

- **GitHub cannot restrict who *opens* a PR**, only who merges.
  `.github/workflows/pr-guard.yml` is the substitute: as a required status check, it blocks
  any PR into the release branch that did not come from the integration branch.
- **"Only I can merge" comes from not granting write access**, not from a checkbox. On a
  personal repo, contributors fork — and a fork PR cannot be merged by its author.

⚠️ Until this is configured, nothing stops a direct push. Convention is not a control.

---

## Quick reference

```bash
# start a slice (product repo)
git checkout dev && git pull && git checkout -b feat/<name>

# start a slice (dev-ops, project <project>)
git checkout <project>-dev && git pull && git checkout -b feat/<name>

# release: open a PR dev → main (or <project>-dev → <project> in dev-ops). The HUMAN merges it.

# shared repo — add something every project should have
git checkout main && <edit> && git commit && git checkout <project> && git merge main
```
