---
title: GitHub setup — visibility, branch protection, and who can merge
status: current
last_updated: 2026-08-23
applies_to: [drovi-backend, drovi-frontend, dev-ops, global-context]
---

# GitHub setup

Turns `branching-strategy.md` from convention into enforcement. **Until this is done,
nothing stops a direct push to `main`.**

## Read this first — two things GitHub cannot do

### 1. GitHub cannot restrict *who opens* a pull request

There is no setting for it. Anyone who can see a public repo can open a PR against any
branch, including `main`. What you *can* control is **who merges**.

Two mitigations, both already in the repos:

- `.github/workflows/pr-guard.yml` fails any PR into the release branch that did not come
  from `dev`. Made a **required status check**, such a PR cannot be merged.
- `.github/CODEOWNERS` routes every PR to you for review.

### 2. "Restrict who can push to matching branches" is **organization-only**

These repos are personal (`mudgalprashant/…`), not owned by an organization, so that
setting does not appear. It does not matter, because of how personal repos work:

> On a personal repo, only the owner and **invited collaborators** can push at all.
> Everyone else must fork and open a PR from their fork — and a fork PR **cannot** be
> merged by its author.

**So "only I can merge" is achieved by not granting anyone write access.** Contributors
fork. That is the whole control, and it is stronger than any checkbox.

⚠️ The moment you add a collaborator with **Write**, they can merge any PR that satisfies
protection. If you ever need collaborators *and* merge control, the repo has to move to an
organization, where bypass lists and push restrictions exist.

---

## Step 1 — Make each repo public

Public repos get branch protection, rulesets and unlimited Actions minutes on the free
plan. Private repos do not.

`Settings` → `General` → scroll to **Danger Zone** → **Change visibility** → *Make public*.

| Repo | Visibility | Consequence |
| --- | --- | --- |
| `drovi-backend` | **public** ✅ done | branch protection available |
| `drovi-frontend` | **public** ✅ done | branch protection available |
| `dev-ops` | **public** ✅ done | branch protection available |
| `global-context` | **private, deliberately** | **no branch protection** on the free plan — see Step 5 |

`global-context` stays private by choice. It is a working index for agents rather than
something a contributor reads, and it carries no code. The trade is that its `drovi` branch
is unprotected: nothing prevents a force-push or a deletion there. Treat that as a known,
accepted gap rather than an oversight — and keep a local clone, because the remote is the
only other copy.

**Before you do:** confirm nothing secret is in the history. All four repos were
history-reset on 2026-08-23 to a single commit each and scanned — no keys, no `.env`, no
private key files. Every credential lives in the Render dashboard, and `render.yaml`
declares them `sync: false`. If you ever add a commit that touches a credential, rotate it
rather than trying to purge it.

---

## Step 2 — Make `dev` the default branch

**The highest-leverage step, and the easiest to skip.** The default branch is what a PR
targets unless the author changes it — so this alone routes almost every contribution to
`dev` without anyone reading a doc.

`Settings` → `General` → **Default branch** → pencil icon → select `dev` → *Update*.

| Repo | Default branch |
| --- | --- |
| `drovi-backend` | `dev` |
| `drovi-frontend` | `dev` |
| `dev-ops` | `dev` |
| `global-context` | `drovi` (it has no `dev`, by design) |

Also on that page, tick **Automatically delete head branches** so merged `feat/…` branches
clean themselves up.

---

## Step 3 — Protect the release branch

`Settings` → `Branches` → **Add branch protection rule**.

Branch name pattern: **`main`** — except in `dev-ops`, where it is **`drovi`**, and in
`global-context`, see Step 5.

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | ✅ | no direct commits to the release branch, ever |
| ↳ Required approvals | **0** while you are solo | ⚠️ see the trap below |
| ↳ Require review from Code Owners | ⬜ while solo, ✅ once approvals ≥ 1 | routes PRs to you |
| Require status checks to pass | ✅ | |
| ↳ Select **`release-prs-come-from-dev`** | ⏳ **not yet selectable** — see below | this is what blocks a PR into `main` that skipped `dev` |
| ↳ Select your CI check too | ⏳ same | |
| Require branches to be up to date before merging | ✅ | stops a green PR merging onto a moved base |
| Require conversation resolution | ✅ | |
| Do not allow bypassing the above settings | ⬜ **leave OFF while solo** | ⚠️ see the trap below |
| Allow force pushes | ⬜ | |
| Allow deletions | ⬜ | |

### ⚠️ Status checks cannot be selected until they have run once

GitHub only lists checks it has actually seen report on the repository. Until
`pr-guard.yml` has run on at least one pull request, `release-prs-come-from-dev` does not
appear in the picker — which is why this step is deferred rather than skipped.

**The gap this leaves is real and worth naming.** Until the check is *required*, the guard
is **advisory**: a PR into `main` from a stray branch will show a red ✗, and can still be
merged. The rule is enforced by you noticing, not by GitHub.

To close it:

1. Merge these PRs into `dev` — the workflow file has to exist on the branch first.
2. Open any PR into `main`. The guard runs and reports.
3. Return to the `main` protection rule → **Require status checks to pass** → the check is
   now in the list. Select it. Do the same for CI once a CI workflow reports.

Put a reminder somewhere you will see it. This is the single step most likely to be
forgotten, and it is the one that turns the branch model from convention into enforcement.

### ⚠️ The solo-maintainer trap

**Do not set required approvals to 1 while you are the only maintainer.** GitHub does not
let you approve your own pull request, so a required approval plus *"Do not allow
bypassing"* locks you out of your own release branch — the PR can never be merged by
anyone.

While solo: **approvals 0, bypassing allowed.** You still cannot push to `main` directly,
and the guard check still blocks anything that did not come from `dev`. The PR exists so
there is always a reviewable diff before a release.

**When you add your first contributor**, flip both: approvals → 1, Code Owners review →
on, and *"Do not allow bypassing"* → on. At that point someone else can approve you.

---

## Step 4 — Protect `dev`

`Settings` → `Branches` → **Add branch protection rule** → pattern **`dev`**.

| Setting | Value |
| --- | --- |
| Require a pull request before merging | ✅ |
| ↳ Required approvals | **0** while solo → **1** once you have contributors |
| Require status checks to pass | ✅ — your CI check |
| Require branches to be up to date before merging | ✅ |
| Require conversation resolution | ✅ |
| Allow force pushes | ⬜ |
| Allow deletions | ⬜ |

`dev` is deliberately **open to PRs from anyone**. Contributors fork, branch
`feat/<name>` or `fix/<name>`, and open a PR here. They cannot merge it — you do.

---

## Step 5 — `global-context` (private, unprotected)

Two deliberate choices compound here:

- it has **no `dev` branch** — its context must be correct the moment the code it describes
  lands, so it is committed to `drovi` alongside the change
- it stays **private**, so branch protection is unavailable on the free plan

**Result: `drovi` in `global-context` has no protection at all.** A force-push or a branch
deletion there is unrecoverable from GitHub alone.

Mitigations, in order of effort:

| Do this | Buys |
| --- | --- |
| Keep a local clone and `git fetch` it periodically | a second copy of every commit |
| Tag releases (`git tag ctx-YYYYMMDD && git push --tags`) | named recovery points |
| Make it public later, or move it into an org | real protection |

---

## Step 6 — Verify it actually works

Do not trust the checkboxes. Test each control once:

```bash
# 1. A direct push to the release branch must be REJECTED.
git checkout main && git commit --allow-empty -m "test" && git push origin main
#    expect: "protected branch hook declined"
git reset --hard origin/main

# 2. A PR into main from a feature branch must FAIL its check.
git checkout dev && git checkout -b feat/protection-test
git commit --allow-empty -m "test" && git push -u origin feat/protection-test
#    open a PR into main → the `release-prs-come-from-dev` check must fail
#    then close the PR and delete the branch
```

If either succeeds, protection is not on the branch you think it is. A pattern of `main`
does not match `dev-ops`'s release branch, which is `drovi`.

---

## What each rule buys you

| Goal | Enforced by |
| --- | --- |
| Nobody commits to `main` | Branch protection: require a PR ✅ |
| Only `dev` reaches `main` | `pr-guard.yml` as a **required** status check ⏳ *advisory until selected — see Step 3* |
| Only you merge | Personal repo + **no write collaborators** |
| Every PR reaches you | `.github/CODEOWNERS` |
| Anyone can contribute to `dev` | Public repo, fork + PR, `dev` as default branch |
| A release is a decision, not an accident | The `dev` → `main` PR is opened and merged by you |
