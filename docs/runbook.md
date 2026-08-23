---
title: Operational runbook
status: current
last_updated: 2026-08-22
---

# Runbook

Every procedure here assumes you can reach the Supabase SQL editor and the Render
dashboard. Most controls are **database rows**, deliberately, so you can act without
waiting for a build.

## Ownership — which runbook

| Symptom | Here | Elsewhere |
| --- | --- | --- |
| Spend, storage, connections, deploys | ✅ | |
| A sandbox returns the wrong body | | `observability.md` → the end-to-end trace |
| A schema or runtime bug | | `global-context/drovi-backend-context/playbooks/debug-failure.md` |

---

## First deploy: the four failures, in the order they happen

Every one of these was hit for real on 2026-08-23. Each looks like a different problem
than it is, which is why they are written down rather than left to be rediscovered.

The application now **fails fast with an explanatory message** for the first two, and a test
guards the third. This section explains what to look for if you meet them anyway — on a new
environment, or from an older image.

### 1. `'url' must start with "jdbc"`

`DROVI_DB_URL` holds a **libpq** URL. Supabase shows you that form; Spring needs JDBC.

```
✗ postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
✓ jdbc:postgresql://aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
```

Prepend `jdbc:`, delete the `<user>:<password>@` part. Reads like a Flyway bug because the
throw happens inside Flyway's initialisation.

### 2. `password authentication failed for user "postgres"`

**Read the username in that message.** If it says `postgres` rather than
`postgres.<project-ref>`, the password is not the problem — `DROVI_DB_USERNAME` never
reached the app, and `application.yaml`'s local-development default took over.

Set both, exactly:

```
DROVI_DB_USERNAME=postgres.<project-ref>
DROVI_DB_PASSWORD=<the Supabase database password>
```

Supabase's session pooler requires the project ref in the username. Lost the password?
Supabase → **Settings → Database → Reset database password**.

### 3. `Found non-empty schema(s) "public" but no schema history table`

Supabase's `public` schema is **not empty** on a new project, and Flyway will not migrate
into an occupied schema without a baseline.

Fixed in `application.yaml`: `baseline-on-migrate: true` **and `baseline-version: 0`**.

⚠️ The second line is the load-bearing one. `baseline-version` defaults to **1**, and Flyway
applies only migrations *above* the baseline — so at the default, `V1__baseline` is silently
skipped. Flyway reports success, the app starts, and the first symptom is Hibernate
complaining about a missing table, which points nowhere near this setting.

### 4. `No open ports detected`

Not a port problem. It is Render still scanning while the app dies during startup — always
a **symptom**, never the cause. Scroll up for the real exception.

### Verifying a good deploy

```bash
curl https://drovi-backend.onrender.com/actuator/health
# {"status":"UP"}
```

`UP` means Flyway applied all three migrations against Supabase and Hibernate validated the
schema — the strongest single signal that the deployment is genuinely working.

Then confirm the migrations landed:

```sql
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;
-- expect versions 1, 2 and 3, all success = true
```

---

## Incident: model spend is running away

**Severity 1.** This is the fastest way to lose real money in this system.

1. **Stop the bleeding first, diagnose second.**

   ```sql
   UPDATE app_config SET value = 'false' WHERE key = 'ai.enabled';
   ```

   This fails new generations closed with `CAPPED`. It does **not** stop sandboxes
   serving — existing projects keep working, so users are inconvenienced, not broken.

   ⚠️ The value is cached in-process for up to 10 minutes. If the running instance has not
   picked it up, restart the service from Render — a restart is cheap and certain.

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

`generation_job` rows sitting in `RUNNING`. ⚠️ **The sweeper is not written**, so nothing
reclaims them automatically.

```sql
UPDATE generation_job
   SET status = 'FAILED', error_code = 'RECLAIMED', finished_at = now()
 WHERE status = 'RUNNING' AND started_at < now() - interval '10 minutes';
```

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
| `DROVI_GEMINI_API_KEY` | Google AI Studio → add a key → update Render → restart → revoke the old |
| `DROVI_DB_PASSWORD` | Supabase → reset → update Render → restart |
| Firebase service account | Firebase console → new key → update Render → restart → delete the old |

Never rotate by editing a file in a repo. There is no secret value in any repo.

## Escalation

Anything involving a suspected credential compromise: **rotate first, investigate second.**
