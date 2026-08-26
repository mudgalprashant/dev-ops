---
title: GitHub setup — visibility, branch protection, and who can merge
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# GitHub setup

Turns [branching-strategy.md](branching-strategy.md) from convention into enforcement.
**Until this is done, nothing stops a direct push to a release branch.**

Throughout, `<release>` is the repo's release branch (`main` in a product repo,
`<project>` in a shared repo) and `<integration>` is its integration branch (`dev` in a
product repo, `<project>-dev` in `dev-ops`).

## Read this first — two things GitHub cannot do

### 1. GitHub cannot restrict *who opens* a pull request

There is no setting for it. Anyone who can see a public repo can open a PR against any
branch, including the release branch. What you *can* control is **who merges**.

Two mitigations, both already in the repos:

- `.github/workflows/pr-guard.yml` fails any PR into the release branch that did not come
  from the integration branch. Made a **required status check**, such a PR cannot be merged.
- `.github/CODEOWNERS` routes every PR to you for review.

### 2. "Restrict who can push to matching branches" is **organization-only**

A personal repo does not show that setting. It does not matter, because of how personal
repos work:

> On a personal repo, only the owner and **invited collaborators** can push at all.
> Everyone else must fork and open a PR from their fork — and a fork PR **cannot** be
> merged by its author.

**So "only I can merge" is achieved by not granting anyone write access.** Contributors
fork. That is the whole control, and it is stronger than any checkbox.

⚠️ The moment you add a collaborator with **Write**, they can merge any PR that satisfies
protection. If you ever need collaborators *and* merge control, the repo has to move to an
organization, where bypass lists and push restrictions exist.

---

## Step 1 — Decide visibility per repo

Public repos get branch protection, rulesets and unlimited Actions minutes on the free
plan. Private repos get none of that.

`Settings` → `General` → **Danger Zone** → **Change visibility**.

| Repo | Recommended | Consequence |
| --- | --- | --- |
| `<project>-backend` | public | branch protection available |
| `<project>-frontend` | public | branch protection available |
| `dev-ops` | public | branch protection available |
| `global-context` | private, deliberately | **no branch protection** on the free plan — see Step 5 |

**Before you make anything public:** confirm nothing secret is in the history. Scan it, not
just the working tree. If you find a commit that touches a credential, **rotate the
credential** rather than trying to purge the history — see [secrets.md](secrets.md).

---

## Step 2 — Make the integration branch the default

**The highest-leverage step, and the easiest to skip.** The default branch is what a PR
targets unless the author changes it — so this alone routes almost every contribution to
the integration branch without anyone reading a doc.

`Settings` → `General` → **Default branch** → pencil icon → select → *Update*.

| Repo | Default branch |
| --- | --- |
| `<project>-backend`, `<project>-frontend` | `dev` |
| `dev-ops` | `<project>-dev` |
| `global-context` | `<project>` (it has no integration branch, by design) |

⚠️ In a shared repo the default branch can name only **one** project. Once a second project
exists, the default is a convenience for whoever works there most, not a statement about
precedence — and every contributor has to retarget deliberately. Say so in the README.

Also on that page, tick **Automatically delete head branches** so merged `feat/…` branches
clean themselves up. (Check afterwards that they actually do; stale merged branches
accumulate quickly and each one looks like unlanded work.)

---

## Step 3 — Protect the release branch

`Settings` → `Branches` → **Add branch protection rule**.

Branch name pattern: **`<release>`**. In `dev-ops` that is the project name, not `main`.

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | ✅ | no direct commits to the release branch, ever |
| ↳ Required approvals | **0** while you are solo | ⚠️ see the trap below |
| ↳ Require review from Code Owners | ⬜ while solo, ✅ once approvals ≥ 1 | routes PRs to you |
| Require status checks to pass | ✅ | |
| ↳ Select **`release-prs-come-from-dev`** | ⏳ **not yet selectable** — see below | this is what blocks a PR that skipped the integration branch |
| ↳ Select your CI check too | ⏳ same | |
| Require branches to be up to date before merging | ✅ | stops a green PR merging onto a moved base |
| Require conversation resolution | ✅ | |
| Do not allow bypassing the above settings | ⬜ **leave OFF while solo** | ⚠️ see the trap below |
| Allow force pushes | ⬜ | |
| Allow deletions | ⬜ | |

### ⚠️ Status checks cannot be selected until they have run once

GitHub only lists checks it has actually seen report on the repository. Until
`pr-guard.yml` has run on at least one pull request, `release-prs-come-from-dev` does not
appear in the picker — which is why this step is done in two passes rather than skipped.

**The gap this leaves is real and worth naming.** Until the check is *required*, the guard
is **advisory**: a PR into the release branch from a stray branch shows a red ✗ and can
still be merged. The rule is enforced by you noticing, not by GitHub.

To close it:

1. Merge the workflow into the integration branch — the file has to exist on a branch first.
2. Open any PR into the release branch. The guard runs and reports.
3. Return to the protection rule → **Require status checks to pass** → the check is now in
   the list. Select it. Do the same for CI once a CI workflow reports.

Put a reminder somewhere you will see it. This is the single step most likely to be
forgotten, and it is the one that turns the branch model from convention into enforcement.

### ⚠️ The solo-maintainer trap

**Do not set required approvals to 1 while you are the only maintainer.** GitHub does not
let you approve your own pull request, so a required approval plus *"Do not allow
bypassing"* locks you out of your own release branch — the PR can never be merged by
anyone.

While solo: **approvals 0, bypassing allowed.** You still cannot push to the release branch
directly, and the guard check still blocks anything that did not come from the integration
branch. The PR exists so there is always a reviewable diff before a release.

**When you add your first contributor**, flip both: approvals → 1, Code Owners review →
on, and *"Do not allow bypassing"* → on. At that point someone else can approve you.

---

## Step 4 — Protect the integration branch

`Settings` → `Branches` → **Add branch protection rule** → pattern **`<integration>`**.

| Setting | Value |
| --- | --- |
| Require a pull request before merging | ✅ |
| ↳ Required approvals | **0** while solo → **1** once you have contributors |
| Require status checks to pass | ✅ — your CI check |
| Require branches to be up to date before merging | ✅ |
| Require conversation resolution | ✅ |
| Allow force pushes | ⬜ |
| Allow deletions | ⬜ |

The integration branch is deliberately **open to PRs from anyone**. Contributors fork,
branch `feat/<name>` or `fix/<name>`, and open a PR here. They cannot merge it — you do.

---

## Step 5 — `global-context` (private, therefore unprotected)

Two deliberate choices compound here:

- it has **no integration branch** — its context must be correct the moment the code it
  describes lands, so it is committed to the project branch alongside the change
- it stays **private**, so branch protection is unavailable on the free plan

**Result: its project branches have no protection at all.** A force-push or a branch
deletion there is unrecoverable from GitHub alone.

Mitigations, in order of effort:

| Do this | Buys |
| --- | --- |
| Keep a local clone and `git fetch` it periodically | a second copy of every commit |
| Tag checkpoints (`git tag ctx-YYYYMMDD && git push --tags`) | named recovery points |
| Make it public later, or move it into an org | real protection |

⚠️ A clone that has not been fetched in weeks is not a backup of what is on the remote —
and a remote that has moved ahead of your clone is the normal state, not an anomaly. Fetch
before you rely on it.

---

## Step 6 — Verify it actually works

Do not trust the checkboxes. Test each control once:

```bash
# 1. A direct push to the release branch must be REJECTED.
git checkout <release> && git commit --allow-empty -m "test" && git push origin <release>
#    expect: "protected branch hook declined"
git reset --hard origin/<release>

# 2. A PR into the release branch from a feature branch must FAIL its check.
git checkout <integration> && git checkout -b feat/protection-test
git commit --allow-empty -m "test" && git push -u origin feat/protection-test
#    open a PR into <release> → the `release-prs-come-from-dev` check must fail
#    then close the PR and delete the branch
```

If either succeeds, protection is not on the branch you think it is. ⚠️ A pattern of `main`
does not match a shared repo's release branch, which is named after the project.

---

## What each rule buys you

| Goal | Enforced by |
| --- | --- |
| Nobody commits to the release branch | Branch protection: require a PR ✅ |
| Only the integration branch reaches it | `pr-guard.yml` as a **required** status check ⏳ *advisory until selected — see Step 3* |
| Only you merge | Personal repo + **no write collaborators** |
| Every PR reaches you | `.github/CODEOWNERS` |
| Anyone can contribute | Public repo, fork + PR, integration branch as default |
| A release is a decision, not an accident | The release PR is opened and merged by you |
