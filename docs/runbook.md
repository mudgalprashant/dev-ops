---
title: Runbook
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Runbook

Every procedure assumes you can reach the database's SQL console and the host's dashboard.
**Most controls are database rows, deliberately, so you can act without waiting for a
build.**

⚠️ Like [observability.md](observability.md), the incident list is **per project** — one
procedure per silent failure named there. What follows is the shape of a good procedure,
plus the handful of incidents that are genuinely universal.

## What a procedure must contain

1. **How you know it is happening** — the alert line, or the query that shows it.
2. **The first action that stops the bleeding**, in one command, before any diagnosis.
3. **How to verify that action took effect** — a query, not an assumption.
4. **Then** the diagnosis: what causes this, ranked by likelihood.
5. **How to resume**, and what to change so it does not recur at the same threshold.

Ordering matters. A procedure that diagnoses before it stops the bleeding is a procedure
written by someone who has never run it.

## Kill switches

Every subsystem that spends money or calls a third party needs one, and it must be a
database row rather than a deploy.

Write down, for each, exactly what it stops — the sentence people get wrong is the
important one: **a spend kill switch stops *spending*, never *serving*.** The product keeps
working; the metered thing is refused. If a kill switch takes the product down, it is an
outage switch and people will hesitate to use it, which defeats the purpose.

⚠️ **If a configuration value is cached in process, the switch is not immediate.** Record
the actual cache behaviour, verified against the code — not what the configuration
*appears* to say. Where the effective delay is an accident rather than a design, say so, or
the next person will build on it.

## Universal incident: a credential leaked

**Rotate first. Investigate second.** In that order, always. Purging git history is
cleanup, never remediation. See [secrets.md](secrets.md).

## Universal incident: connection exhaustion

Symptom is a pool timeout under load. The pool is small **on purpose** — exhausting a
shared pooler takes out the SQL console you would use to diagnose it.

```sql
SELECT count(*), state FROM pg_stat_activity GROUP BY state;
```

Look for a network call inside a transaction; that is a code bug, not a capacity problem.
**Do not raise the pool size without recomputing the budget against the database's limit.
That is the classic free-tier outage.**

## Universal incident: the database is filling up

Find the biggest consumer, then check it against expectations:

```sql
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;
```

⚠️ It is almost always a per-request log or event table whose purge job was never written.
Delete in batches, then `VACUUM` — a single large `DELETE` on a constrained instance is its
own incident.

## Universal incident: service down, or constantly cold-starting

Check the health endpoint. If cold starts are frequent, the keep-alive has stopped —
check its run history before looking anywhere else.

## Universal: first deploy against a managed Postgres

Four failures happen in this order, and each reads as something else:

1. **`'url' must start with "jdbc"`** — a libpq URL where a JDBC one belongs. It surfaces
   from inside the migration tool, so it reads like a migration bug.
2. **`password authentication failed for user "…"`** — **read the username in the message.**
   If it is the bare user rather than the project-qualified one, the password is not the
   problem: the username variable never reached the app and a local default took over.
3. **`Found non-empty schema(s) "public" but no schema history table`** — a managed
   provider's `public` schema is not empty on a new project. Set baseline-on-migrate **and
   an explicit baseline version of 0**. ⚠️ The second half is the load-bearing one: the
   baseline version defaults to 1 and only migrations *above* it are applied, so at the
   default your first migration is silently skipped.
4. **`No open ports detected`** — not a port problem. The host is still scanning while the
   app dies during startup. **Always a symptom, never the cause** — scroll up for the real
   exception.

## Rollback

Host dashboard → the service → **Deploys** → redeploy a previous successful build.
**Never roll back a migration** — write a fix-forward one. See [deployment.md](deployment.md).

## Escalation

Anything involving a suspected credential compromise: **rotate first, investigate second.**
Anything involving money moving incorrectly: stop the subsystem, then reconcile from the
ledger. Never reconcile by hand-editing the balance — record the correcting event, so the
ledger and the balance still agree afterwards.
