---
title: Operational runbook
status: current
last_updated: 2026-08-22
---

# Runbook

Every procedure here assumes you can reach the Supabase SQL editor and the Render
dashboard. Most controls are **database rows**, deliberately, so you can act without
waiting for a build.

## The alert lines

The service emits `alert.*` lines at WARN when a limit is being **approached** — every other
control announces itself only by refusing somebody. There is nothing scraping this service, so
these are the signal, and they are what a log-based alert in Render should key on:

| Line | Meaning | Procedure |
| --- | --- | --- |
| `alert.spend` | today's model spend is nearing `ai.daily.cost.cap.micros` | [model spend is running away](#incident-model-spend-is-running-away) |
| `alert.storage` | stored sandbox data is nearing `watch.storage.budget.mb` | [the database is filling up](#incident-the-database-is-filling-up) |
| `alert.unmatchedRoutes` | too many sandbox calls matched no endpoint | [generated routes do not match](#incident-generated-routes-do-not-match) |

Each line carries an `action=runbook:…` naming its procedure, and the thresholds are
`app_config` rows (`watch.*`) so they change without a deploy. `watch.enabled = false` silences
all of them — which silences the *warning*, not the limit.

**Every log line carries a correlation id** in brackets. For a request it is the id returned to
the caller in `X-Correlation-Id` and quoted in the error body; for a generation it is the
`generation_job.id`. Grep it.

Set `LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs` to get JSON lines with the MDC as fields, if
something is parsing them.

## Ownership — which runbook

| Symptom | Here | Elsewhere |
| --- | --- | --- |
| Spend, storage, connections, deploys | ✅ | |
| A sandbox returns the wrong body | | `observability.md` → the end-to-end trace |
| A schema or runtime bug | | `global-context/drovi-backend-context/playbooks/debug-failure.md` |

---

## Incident: model spend is running away

**Severity 1.** This is the fastest way to lose real money in this system.

1. **Stop the bleeding first, diagnose second.**

   ```sql
   UPDATE app_config SET value = 'false' WHERE key = 'ai.enabled';
   ```

   This fails new generations closed with `CAPPED`. It does **not** stop sandboxes
   serving — existing projects keep working, so users are inconvenienced, not broken.

   ⚠️ **Today this takes effect on the very next model call**, because caching is not
   actually enabled in the application — nothing declares `@EnableCaching`, so
   `AppConfigService`'s `@Cacheable` is inert (`drovi-backend` thread Q). Do not rely on
   that: it is an accident, not a design, and the moment Q is resolved by enabling caching
   the value is cached in-process for up to 10 minutes.

   Either way the safe move is unchanged — **verify, then restart if in doubt.** A restart
   from Render is cheap and certain:

   ```sql
   -- Proof it took: a call attempted after the UPDATE is ledgered as CAPPED.
   SELECT status, count(*) FROM ai_call
    WHERE created_at > now() - interval '5 minutes' GROUP BY 1;
   ```

2. **See where it went.**

   ```sql
   SELECT purpose, model, count(*), sum(cost_micros)/1e6 AS usd
     FROM ai_call WHERE created_at > now() - interval '24 hours'
    GROUP BY 1,2 ORDER BY 4 DESC;
   ```

3. **Identify the account.**

   ```sql
   SELECT account_id, sum(cost_micros)/1e6 AS usd FROM ai_call
    WHERE created_at > now() - interval '24 hours' GROUP BY 1 ORDER BY 2 DESC LIMIT 5;
   ```

4. **Common causes**, in order of likelihood: a retry loop on unparseable model output
   (`ai.max.attempts` too high); one account seeding enormous projects; a purpose routed
   to a more expensive model than intended.

   The `status` column narrows it fast — the ledger records refusals, not just successes:

   | Mostly | Read it as |
   | --- | --- |
   | `OK` | genuine usage. Look at `purpose` and the account, not at a bug |
   | `ERROR` | a retry loop. Each attempt is billed for its input tokens; lower `ai.max.attempts` |
   | `TIMEOUT` | the provider is slow and we gave up — **these may still have been billed** |
   | `REFUSED` | something is retrying a refusal, which spends money to be told no again. That is a bug |
   | `CAPPED` | the controls are already holding. Nothing was sent; spend is not from these |

5. **Re-enable with a lower cap**, not with the same one:

   ```sql
   UPDATE app_config SET value = '1000000' WHERE key = 'ai.daily.cost.cap.micros';
   UPDATE app_config SET value = 'true'    WHERE key = 'ai.enabled';
   ```

## Incident: the database is filling up

Supabase free is 500 MB, shared by every tenant's sandbox data.

1. **Find the biggest consumer.**

   ```sql
   SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables
    ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;
   ```

2. ⚠️ **It is almost certainly `mock_request_log`.** Its retention purge is **not
   written**, so it grows without bound. The manual purge:

   ```sql
   DELETE FROM mock_request_log WHERE created_at < now() - interval '7 days';
   ```

   Delete in batches on a busy table. Follow with `VACUUM` — the space is not returned to
   the filesystem otherwise.

3. If sandbox data is the cause, find the projects:

   ```sql
   SELECT project_id, sum(record_count) AS records, pg_size_pretty(sum(stored_bytes)) AS bytes
     FROM sandbox_collection GROUP BY 1 ORDER BY sum(stored_bytes) DESC LIMIT 10;
   ```

   Quotas should have prevented this. If a project is over its plan limit, the counters
   drifted — suspect a direct SQL insert that bypassed the trigger, and recompute:

   ```sql
   -- Recount one collection from the source of truth.
   UPDATE sandbox_collection sc
      SET record_count = x.n, stored_bytes = x.b
     FROM (SELECT collection_id, count(*) n, sum(pg_column_size(data)) b
             FROM sandbox_record GROUP BY 1) x
    WHERE sc.id = x.collection_id AND sc.id = :collectionId;
   ```

## Incident: DB connection exhaustion

Symptoms: `HikariPool-1 - Connection is not available`, timeouts under light load.

1. Check the pool: `DROVI_DB_POOL_MAX` is **2** on Render free, on purpose. The Supabase
   free pooler is shared, and exhausting it takes out the SQL editor you would use to
   diagnose the problem.
2. `SELECT count(*), state FROM pg_stat_activity GROUP BY state;`
3. Look for a long transaction holding a connection — most likely an HTTP call inside
   `@Transactional`. That is a code bug (see `do-not.md`), not a tuning problem.
4. **Do not raise the pool size without recomputing the budget.** That is the classic
   free-tier outage.

## Incident: generations are stuck

`generation_job` rows sitting in `RUNNING`. **The sweeper now handles this**, so before
touching anything, check whether it is running.

A stranded job is not merely untidy: it leaves its project `GENERATING`, and **a GENERATING
project does not serve**. Someone's sandbox is dark until the job is resolved.

```sql
-- Is the sweeper on at all?
SELECT value FROM app_config WHERE key = 'sweeper.enabled';

-- What is actually stuck, and for how long?
SELECT id, kind, attempt, now() - started_at AS running_for
  FROM generation_job WHERE status = 'RUNNING' ORDER BY started_at;
```

It reclaims a job after `ai.job.timeout.seconds` — **requeuing** it if attempts remain, since a
runner killed by a deploy did nothing wrong, and failing it only once they are exhausted. It
skips whatever the runner is currently working on, so a genuinely slow job is left alone.

If it is off, turn it on; that is the fix. Only if the sweeper itself is broken should you do
this by hand, and prefer requeuing to failing:

```sql
UPDATE generation_job
   SET status = 'QUEUED', error_code = 'RECLAIMED', updated_at = now()
 WHERE status = 'RUNNING' AND started_at < now() - interval '10 minutes';
```

⚠️ Whichever you do, **check the projects**. A job that ends `FAILED` moves its project out of
`GENERATING` through the pipeline; one you edit in SQL does not:

```sql
SELECT id, name, status FROM sandbox_project WHERE status = 'GENERATING';
```

## Incident: generated routes do not match

**Alert:** `alert.unmatchedRoutes`. A large share of sandbox calls in the last hour matched no
endpoint.

This is the one alert about the **product** rather than the platform, and the roadmap names it
as *the* signal that generation quality is not good enough. Users are hitting 404s on their own
integration and, reasonably, blaming their own code.

1. **See whose, and what they were reaching for.** An unmatched call is the most useful row in
   the request log precisely because it is usually a path the generator got wrong.

   ```sql
   SELECT sp.id, sp.name, sp.source_product, count(*) AS misses,
          array_agg(DISTINCT log.method || ' ' || log.path ORDER BY log.method || ' ' || log.path) AS paths
     FROM mock_request_log log
     JOIN sandbox_project sp ON sp.id = log.project_id
    WHERE log.endpoint_id IS NULL
      AND log.created_at > now() - interval '1 hour'
    GROUP BY sp.id, sp.name, sp.source_product
    ORDER BY misses DESC LIMIT 20;
   ```

2. **Tell the two cases apart**, because they need opposite responses:

   | Shape | Means | Do |
   | --- | --- | --- |
   | One project, many paths | that generation went badly | the user can revise, or regenerate with the product's spec pasted in |
   | Many projects, similar paths | a systemic problem — a prompt or a model change | look at what changed. Consider routing SPEC back to a previous model |
   | One project, one path, high volume | a caller looping against a route that does not exist | usually the user's own retry loop |

3. **Nothing here is urgent in the way spend is.** No money is being lost and nothing is
   filling. Resist the temptation to change prompts during the alert; establish which of the
   three shapes it is first.

4. **The lasting fix is a supplied spec.** A pasted or linked OpenAPI or Postman document skips
   research entirely and the routes come out exact. If the same product misses repeatedly, that
   is the answer to give the user.

## Incident: a project API key leaked

The user's key, not ours. Revoke rather than delete — the log rows reference it.

```sql
UPDATE project_api_key SET revoked_at = now() WHERE id = :keyId;
```

Then have the owner issue a new one. A project may hold several live keys precisely so
rotation needs no downtime: issue → switch the client → revoke the old.

## Incident: the service is down or cold-starting constantly

1. `curl https://<service>.onrender.com/actuator/health`
2. If cold starts are frequent, the `pg_cron` keep-alive has stopped:
   `SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;`
3. This matters more than it looks: sandboxes are called by other people's *running
   applications*, which read a 30-second cold start as a timeout.

## Deploy

Render builds `drovi-backend` `main` from the `Dockerfile` on push. Flyway runs at startup.

⚠️ **Nothing can deploy today** — `main` HEAD is still `Initial commit` and the product is
an uncommitted working tree.

## Rollback

Render → the service → **Deploys** → redeploy a previous successful build.

⚠️ **Never roll back a migration.** Schema changes are forward-only; write a fix-forward
migration. Rolling the *image* back is safe only when the older image tolerates the newer
schema — which is why a migration must always be compatible with the previously running
version.

## Rotate a secret

Pattern: publish new alongside old → switch → revoke old.

| Secret | Where |
| --- | --- |
| `DROVI_ANTHROPIC_API_KEY` | Anthropic console → add a key → update Render → restart → revoke the old |
| `DROVI_DB_PASSWORD` | Supabase → reset → update Render → restart |
| Firebase service account | Firebase console → new key → update Render → restart → delete the old |

Never rotate by editing a file in a repo. There is no secret value in any repo.

## Escalation

Anything involving a suspected credential compromise: **rotate first, investigate second.**
