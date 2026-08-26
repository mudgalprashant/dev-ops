---
title: Starting a new project from this baseline
status: current
last_updated: 2026-08-26
applies_to: [dev-ops, global-context]
---

# Starting a new project

This is the procedure for adding a project to the two shared repos. It exists because the
first two projects each rediscovered it, and the second one found that step 1 had never
actually been done.

Throughout, `<project>` is the project's slug in lowercase (`bidceleb`), and
`<PROJECT>` is the same in upper case, used as the environment-variable prefix
(`BIDCELEB_`).

---

## 1. The shared repo must have a `main` — check before assuming

```bash
git ls-remote --heads origin main
```

If that prints nothing, `main` does not exist and **must be created before anything else**.
Create it **from the repository's root commit**, never as an orphan:

```bash
root=$(git rev-list --max-parents=0 origin/<any-existing-branch> | tail -1)
git checkout -b main "$root"
# rewrite every file into its project-agnostic form
git commit -am "docs: project-agnostic baseline every project branches from"
git push -u origin main
```

⚠️ **Why the root commit and not `--orphan`.** Every project branch already descends from
that root. A `main` sharing that ancestor can be merged forward into all of them
(`git merge main`). An orphan `main` shares no history, so every forward-merge fails with
*refusing to merge unrelated histories*, and the one mechanic that keeps shared content
identical across projects is dead — silently, and permanently.

Verify before moving on:

```bash
git merge-base --is-ancestor $(git rev-parse main) <project> \
  || git merge-base main <project>      # must print a sha, not nothing
```

## 2. Create the project's branches

```bash
# dev-ops — release line and integration line
git checkout -b <project> main
git push -u origin <project>
git checkout -b <project>-dev <project>
git push -u origin <project>-dev

# global-context — release line only; it has no integration branch, by design
git checkout -b <project> main
git push -u origin <project>
```

The integration branch is **qualified with the project name**. An unqualified `dev` is
unambiguous only while one project exists.

## 3. Adapt the guard to this project's release branch

`.github/workflows/pr-guard.yml` on the `<project>` branch must name that project's own
branches. Two strings change and nothing else:

- `on.pull_request.branches` → `[<project>]`
- the comparison → `github.head_ref != "<project>-dev"`

**Keep the job name `release-prs-come-from-dev` unchanged.** It is the string you select in
branch protection as the required status check; renaming it per project means renaming it
in the GitHub UI too, for no gain.

## 4. Fill in the project-specific content

On the `<project>` branch of `dev-ops`, every doc inherited from `main` has placeholders to
resolve. Work through them in this order — later ones depend on earlier ones:

| Order | File | What to decide |
| --- | --- | --- |
| 1 | `docs/env-matrix.md` | the complete `<PROJECT>_*` inventory, and which are secret |
| 2 | `.env.example` | the same names, **no values**, with the traps that bite |
| 3 | `docs/secrets.md` | which values are secret and which merely look it; the top-tier credential |
| 4 | `docs/free-stack.md` | what is used for each concern in this project |
| 5 | `docs/deployment.md` | the deploy path, and what gates the switchover |
| 6 | `docs/observability.md` | **what fails silently in this product** — the section that cannot be copied |
| 7 | `docs/runbook.md` | one procedure per silent failure named above |
| 8 | `docs/free-tier-budget.md` | what runs out first, quantified, in order |
| 9 | `docs/HUMAN-SETUP-CHECKLIST.md` | accounts, keys and dashboards, in dependency order |
| 10 | `Makefile`, `ci/*.yml`, `README.md` | names and toolchain versions |

Then, on the `<project>` branch of `global-context`, populate the context packages —
`CONTEXT-PROTOCOL.md` there is the authority on how.

⚠️ **`docs/observability.md` and `docs/runbook.md` are the two files that must not be
copied with the names swapped.** Every product fails silently in its own way, and those two
files are where that knowledge lives. A runbook inherited unchanged from another project is
worse than none: it reads as authoritative and describes incidents that cannot happen here.

## 5. Product repos

```bash
git checkout -b main            # first commit: README, .gitignore, LICENSE
git push -u origin main
git checkout -b dev main
git push -u origin dev
```

Then copy the CI workflows out of `dev-ops` — they are authored there and live here, see
[../ci/README.md](../ci/README.md).

## 6. Turn the conventions into enforcement

Follow [github-setup.md](github-setup.md) in full. Nothing above is a control until it is
done, and two of its steps have traps that cost an afternoon each:

- a status check cannot be *required* until it has *run once*, so protection is set in two
  passes; and
- while you are the only maintainer, required approvals stay at **0** — GitHub forbids
  self-approval, and approvals ≥ 1 combined with "do not allow bypassing" locks you out of
  your own release branch with no way back.

## 7. Record it

Add a row to the branch table in this repo's `README.md`, and open the project's
`shared/decisions.md` in `global-context` with the decisions already taken. A decision that
is not written down gets re-litigated within a fortnight.

---

## The completion gate

- [ ] `main` exists in both shared repos and shares history with every project branch
- [ ] `<project>` and `<project>-dev` exist in `dev-ops`; `<project>` exists in `global-context`
- [ ] `pr-guard.yml` on the `<project>` branch names that project's branches
- [ ] No file on the `<project>` branch still says another project's name
- [ ] No placeholder `{{…}}` survives outside a file that documents the placeholder itself
- [ ] Default branch, protection rules and required checks configured and **verified by a
      rejected push**, not by reading the checkboxes
