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

Do this for `drovi-backend`, `drovi-frontend`, `dev-ops`, and `global-context`.

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
| ↳ Select **`release-prs-come-from-dev`** | ✅ | this is what blocks a PR into `main` that skipped `dev` |
| ↳ Select your CI check too | ✅ | |
| Require branches to be up to date before merging | ✅ | stops a green PR merging onto a moved base |
| Require conversation resolution | ✅ | |
| Do not allow bypassing the above settings | ⬜ **leave OFF while solo** | ⚠️ see the trap below |
| Allow force pushes | ⬜ | |
| Allow deletions | ⬜ | |

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

## Step 5 — `global-context`

`global-context` has no `dev` branch on purpose: its context must be correct the moment the
code it describes lands, so it is committed to `drovi` alongside the change.

Protect `drovi` against **force pushes and deletions only** — do *not* require a PR, or
you break the workflow that keeps context and code in the same commit.

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
| Nobody commits to `main` | Branch protection: require a PR |
| Only `dev` reaches `main` | `pr-guard.yml` as a required status check |
| Only you merge | Personal repo + **no write collaborators** |
| Every PR reaches you | `.github/CODEOWNERS` |
| Anyone can contribute to `dev` | Public repo, fork + PR, `dev` as default branch |
| A release is a decision, not an accident | The `dev` → `main` PR is opened and merged by you |
