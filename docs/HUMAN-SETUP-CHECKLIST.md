---
title: Human setup checklist
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Human setup checklist

**Everything a person must do by hand.** Agents cannot create accounts, provision hosts,
spend money, accept terms, or invent secret values.

> **Never paste a value into a doc, a commit, or a chat.** Production values go in the
> host's dashboard, CI values go in a GitHub **Environment**, and production credentials
> never land on a laptop. See [secrets.md](secrets.md).

Each project's branch fills this in with its own services. Every item carries the same
three fields, and an item missing any of them is not finished being written:

- **Feeds** — the environment variable or setting this produces
- **Verify** — how to confirm it actually worked
- **Blocks** — what stays broken until it is done

## Order the list by what blocks what

Not by importance, and not by the order the dashboards appear in. Group as:

1. **Do these first** — they block all local work (usually: the database).
2. **Do these before the feature that needs them** — anything with a cost or a lead time.
   ⚠️ Start any item with an **external approval step** (a payment processor, a developer
   programme, a domain) during setup even if it blocks a much later phase. Approval takes
   days; nothing else on this list does.
3. **Do these before deploying** — host, keep-alive, CI secrets, branch protection.
4. **Do these before real users** — monitoring, and the legal pages.

## The items every project has

| Item | Notes that are always true |
| --- | --- |
| **Database** | take the **session pooler** endpoint, not direct and not transaction mode ([env-matrix.md](env-matrix.md)). Save the password at creation — it is shown once |
| **Identity provider** | copy the **project id**, not the project *name* — they differ once a name is taken. Do **not** download a service-account key unless something genuinely needs one |
| **Host** | sign up with GitHub, deploy from the repo's blueprint, paste each `sync: false` secret when prompted |
| **Keep-alive** | a scheduled request to the health endpoint every 5 minutes. Load-bearing: it prevents both the service spin-down and the database pause |
| **GitHub** | Environment `production` with required reviewers for any CI secret; **never** a repository secret. Then branch protection per [github-setup.md](github-setup.md) |
| **Monitoring** | an uptime monitor on the health endpoint, and an error tracker. *Every failure in a small system is silent until something watches for it* |
| **Legal pages** | terms, privacy, and whatever the product's model requires — live **before** the first real user, not after |

## Deferred — deliberately not doing these

Keep this table too. It is how you stop re-litigating the same suggestions.

| Thing | Why not | When |
| --- | --- | --- |
| Kubernetes | nothing to orchestrate at one instance; the `Dockerfile` **is** the deploy path | more than one instance |
| Docker for local dev | the test suite starts its own database | probably never |
| A cache server | in-process at one instance | more than one instance |
| A custom domain | the host's subdomain has a managed certificate and costs nothing | when the product needs a brand |

## Completion gate

- [ ] Every **Feeds** value is set in the host's dashboard, and nowhere else
- [ ] The health endpoint returns healthy, with migrations applied
- [ ] The keep-alive is scheduled and its last runs succeeded
- [ ] CI is green
- [ ] Branch protection **verified by a rejected push**, not by reading the checkboxes
- [ ] Monitors are live and have fired at least once in a test
- [ ] The legal pages exist

**Anything you could not complete — say so.** It is tracked as `UNKNOWN`, never guessed.
