---
title: Free-tier budget — what runs out first
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Free-tier budget

A project's own branch answers this question **in order, for that product**. The ordering
is what matters: knowing the ceilings is useless without knowing which one you hit first.

## The template

| # | Limit | Ceiling | What consumes it | What happens at the wall | Mitigation |
| --- | --- | --- | --- | --- | --- |
| 1 | | | | | |

Fill it in **sorted by how soon you hit it**, not by size. Then write down the answer to
one question for each row: *does hitting this suspend the service, degrade it, or bill me?*

## Quantified ceilings of the default stack

Verify each against the provider before relying on it; free tiers move.

| Provider | Free ceiling |
| --- | --- |
| Render web service | 512 MB RAM, 0.1 CPU, 750 instance-hours/month, 100 GB bandwidth |
| Supabase | 500 MB database, 1 GB file storage, 5 GB egress, 2 projects |
| Firebase Spark | ~3,000 daily active users |
| GitHub Actions | unlimited on public repos; 2,000 minutes/month private |
| Sentry | ~5,000 errors/month |
| UptimeRobot | 50 monitors at 5-minute intervals |

⚠️ 750 instance-hours against **744 hours in a 31-day month** is roughly six hours of
margin. One always-on free service fits; two do not.

## The three that catch people out

1. **Unbounded log or event tables.** Anything that writes a row per served request grows
   without limit and will hit the database ceiling long before traffic hits any other one.
   **Write the purge job in the same change that adds the table** — a retention setting
   with no job behind it is decorative, and it is always discovered during an incident.
2. **A rate limit is a wall, not a bill.** Requests-per-minute ceilings on third-party APIs
   fail the request rather than charging you, so a job that fans out breaks where a job
   that paces itself succeeds.
3. **Memory is the tightest technical limit.** If the service OOMs, the honest fix is
   usually the host's smallest paid instance, not a week of tuning.

## Reviewing this

Re-check when traffic changes by an order of magnitude, when a new table starts growing
per-request, or when a provider changes its plans. A budget nobody has re-read in six
months is a guess.
