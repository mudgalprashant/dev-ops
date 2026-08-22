---
title: Branching strategy
status: current
last_updated: 2026-08-21
applies_to: [drovi-backend, drovi-frontend, dev-ops, global-context]
---

# Branching strategy

Two kinds of repo live in this project, and they need opposite rules.

- **Product repos** — `drovi-backend`, `drovi-frontend`. One product each. Normal
  trunk-based flow.
- **Shared repos** — `dev-ops`, `global-context`. These serve *other projects too*.
  Drovi content must never reach a branch another project reads.

---

## Product repos — `drovi-backend`, `drovi-frontend`

```
main                    deployable. tagged. protected.
 └── dev                integration. everything lands here via PR + green CI. protected.
      ├── feat/<slice>  one vertical slice, short-lived
      ├── fix/<thing>
      └── chore/<thing>
```

**Rules**

| Rule | Why |
| --- | --- |
| Branch off `dev`, PR into `dev`, squash-merge, delete the branch | Keeps `dev` history one line per slice, so `git log --oneline` reads as a changelog |
| Never commit directly to `dev` or `main` | CI is the gate; a direct push skips it |
| `dev` → `main` only when a slice is genuinely deployable — merge commit, then tag `v0.x.y` | `main` answers "what is running in production", nothing else |
| A branch name states the *slice*, not the file — `feat/sandbox-generation`, not `feat/add-entity` | A slice that cannot be named in three words is too big |
| Rebase your branch on `dev` before opening the PR; never rebase after review starts | Reviewers lose their place when history moves under them |

**Supersedes** shared decision #6 ("no branch is merged to `main` in any repo"). That
was a reasonable holding position while nothing was deployable. It stops being reasonable
the moment something is: with no promotion path, `dev` becomes both the integration branch
and the release branch, and there is then no way to hotfix production without shipping
whatever else is half-done on `dev`.

---

## Shared repos — `dev-ops`, `global-context`

```
main                     cross-project content ONLY
 ├── drovi               long-lived. ALL drovi content.
 │    └── drovi/<topic>  short-lived, for a change too big for one commit
 └── <other-project>     same shape, one branch per project
```

**The one rule that matters: merges go one way.**

```
main ──────────────▶ drovi          ALLOWED  (pick up shared conventions)
drovi ─────────✗───▶ main           NEVER    (leaks drovi into other projects)
drovi ─────────✗───▶ <other>        NEVER
```

**Rules**

| Rule | Why |
| --- | --- |
| `drovi` is **never** merged into `main` | `main` is what a *new* project branches from. One drovi-specific env var landing there and every future project inherits it |
| Content genuinely useful to every project is committed **to `main` directly**, then picked up with `git merge main` into `drovi` | Makes the direction explicit. If you find yourself wanting to merge upward, you wrote it on the wrong branch |
| A new project branches from `main`, never from `drovi` | Same reason |
| Forward-merge `main` into `drovi` whenever `main` moves | Otherwise the project branches quietly drift off the shared baseline and nobody notices for months |
| If something on `drovi` turns out to be generic, **rewrite it onto `main`** rather than cherry-picking | Cherry-picking carries drovi's framing with it. Generic content should read as generic |

**Why one branch per project instead of one repo per project:** the shared content
(conventions, security baseline, glossary) is small and changes rarely, but it must stay
identical everywhere. In separate repos it would be copy-pasted and diverge within a
month. On branches, `git merge main` keeps it honest and the divergence is visible in
one command.

---

## Working across repos

A change that spans repos (contract change, new env var, new secret) needs its branches
named identically in each repo it touches, and the PRs cross-linked. Land them in this
order, because each depends on the one before:

1. `global-context` — the contract or decision, on `drovi`
2. `dev-ops` — env vars, CI, deployment, on `drovi`
3. `drovi-backend` — the server side, on `feat/<slice>`
4. `drovi-frontend` — the client side, on `feat/<slice>`

**The API contract is the interlock.** `global-context/shared/api-contract.md` is
authoritative. A `frozen` endpoint may not change shape without a new version and a note
in that file — the app is allowed to build against `frozen` and will break otherwise.

---

## Quick reference

```bash
# product repo — start a slice
git checkout dev && git pull && git checkout -b feat/sandbox-generation

# shared repo — start drovi work
git checkout drovi && git pull

# shared repo — pick up a change made on main
git checkout drovi && git merge main

# shared repo — add something every project should have
git checkout main && <edit> && git commit && git checkout drovi && git merge main
```
