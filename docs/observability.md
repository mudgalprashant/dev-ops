---
title: Observability — what we watch, and how to trace one sandbox call
status: current
last_updated: 2026-08-22
---

# Observability

Two things can hurt here, and they are not the usual ones. **Spend** can run away quietly,
and a **sandbox can lie** — return a plausible response that is subtly not what the real
product would send. Neither shows up as a 500.

## What to watch

### The money signals

| Signal | Source | Why |
| --- | --- | --- |
| Model spend today | `SELECT sum(cost_micros) FROM ai_call WHERE created_at >= date_trunc('day', now())` | The only per-use cost in the stack |
| Spend by purpose | `ai_call` grouped by `purpose` | `SEED` dominating is the signal to route it cheaper |
| Failed calls that still cost | `ai_call WHERE status <> 'OK' AND input_tokens > 0` | A retry loop bills even when nothing succeeds |
| Storage per project | `sandbox_collection.stored_bytes` summed per project | Supabase free is 500 MB total |
| `mock_request_log` size | `pg_total_relation_size('mock_request_log')` | ⚠️ **the purge job is not written** — this table grows without bound |

### The product signals

| Signal | Source | Why it matters |
| --- | --- | --- |
| **Unmatched route rate** | `mock_request_log WHERE endpoint_id IS NULL` | **The single most valuable metric here.** It usually means the generator invented a path the real product does not have — a correctness failure the user experiences as a 404 |
| Rule hit rate | `mock_request_log WHERE rule_id IS NOT NULL` | A sandbox answering mostly from rules has drifted away from "data, not scripts" |
| 502 `SANDBOX_MISCONFIGURED` | `error_code` | An endpoint bound to a deleted collection — always our bug, never the caller's |
| 507 `QUOTA_EXCEEDED` | `error_code` | Users hitting plan limits. Product signal as much as an ops one |
| Generation failures | `generation_job WHERE status = 'FAILED'` | |
| Stuck jobs | `generation_job WHERE status = 'RUNNING' AND started_at < now() - interval '5 min'` | ⚠️ **the sweeper is not written**, so these stay stuck forever |

### The infrastructure signals

| Signal | Alert when |
| --- | --- |
| `/actuator/health` | not `UP` for 2 consecutive checks |
| Render cold starts | frequent — the keep-alive has stopped |
| Hikari active connections | at `DROVI_DB_POOL_MAX` for a sustained period |
| Supabase connection count | approaching the project limit |

## Silence is a failure mode here too

A sandbox that nobody calls looks identical to a sandbox that is broken. If a project went
from steady traffic to zero, that is worth surfacing to its owner — their integration
probably broke, and Drovi is the last thing they will suspect.

## "My sandbox returned the wrong thing" — end-to-end trace

The most common support question. Work in this order; the answer is almost always found
in the first two steps.

### 1. Find the call

```sql
SELECT created_at, method, path, query, status_code, endpoint_id, rule_id, error_code, latency_ms
  FROM mock_request_log
 WHERE project_id = :projectId
 ORDER BY created_at DESC
 LIMIT 20;
```

| What you see | What it means |
| --- | --- |
| No row at all | The call never reached Drovi. Wrong base URL, wrong project key, or their client cached DNS. **Check the URL before anything else** |
| `endpoint_id IS NULL` | Nothing matched. Go to step 2 |
| `rule_id IS NOT NULL` | An override answered — this is usually the whole explanation |
| `status_code = 401` | Auth mode mismatch; the caller is not sending the key the project expects |
| `status_code = 507` | The project is full. Not a bug |

### 2. If nothing matched — compare the paths

```sql
SELECT method, path_template, specificity, behavior
  FROM api_endpoint WHERE project_id = :projectId ORDER BY specificity DESC;
```

Compare against the `path` from step 1. Look for: a method mismatch, a version prefix the
generator omitted (`/v1`), a placeholder that should be a literal, or a plural/singular
slip. **This is a generation-quality bug**, and the fix is to regenerate or correct the
endpoint — not to add a rule.

### 3. If an endpoint matched but the body is wrong

| Check | Query |
| --- | --- |
| Is a rule intercepting? | `SELECT * FROM response_rule WHERE endpoint_id = :id ORDER BY priority` — remember an empty `{}` matcher matches everything |
| Is the data there? | `SELECT record_key, data FROM sandbox_record WHERE collection_id = :cid LIMIT 5` |
| Is the filter silently excluding? | Query params only filter when `record_schema` declares them. An undeclared param is ignored; a declared one with a wrong value matches nothing |
| Is the envelope wrong? | `SELECT response_template FROM api_endpoint WHERE id = :id` — a placeholder naming something the behaviour never produced renders as `null` |

### 4. If it is slow

`latency_ms` in the log **includes** `sandbox_project.latency_ms`, which the user may have
set deliberately to simulate the real product. Check that before investigating a
performance problem that does not exist.

## Make the trace fast

Keep `runtime.log.enabled = true`. It is the only reason any of the above works, and
turning it off to save storage blinds the inspector while the runtime keeps serving —
which is exactly when you will wish you had it.
