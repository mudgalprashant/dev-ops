---
title: Observability — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend]
---

# Observability — bidceleb

The method is canonical on `main`. This file answers the question that method asks.

## What can go wrong here without producing a 500

Four things, and none of them shows up as an error:

1. **Money is taken and popularity does not move.** The user paid, the provider is happy,
   the board is unchanged. The user's own evidence says we stole from them, and from our
   side every log line is green. This is the worst failure this product has.
2. **Popularity is minted without payment.** A forged or replayed webhook, or a settlement
   path that trusts the browser's success redirect. Nothing fails; the board is simply a
   lie, and the whole product is the board being true.
3. **The board and the ledger disagree.** `celebrity.popularity_cents` drifts from
   `SUM(boost)`. Every page renders, every query returns, the number is wrong.
4. **Submissions queue silently.** People pay $100, nothing happens, and the only symptom
   is a support email weeks later.

Two of the four are financial and two are integrity. An uptime monitor sees none of them.

## Money signals

```sql
-- boosts created but never settled (the incident-1 detector)
SELECT count(*), min(created_at)
FROM boost
WHERE status = 'PENDING' AND created_at < now() - interval '15 minutes';

-- ledger vs board: MUST return zero rows
SELECT c.id, c.slug, c.popularity_cents, coalesce(sum(b.amount_cents), 0) AS ledger
FROM celebrity c
LEFT JOIN boost b ON b.celebrity_id = c.id AND b.status = 'SETTLED'
GROUP BY c.id, c.slug, c.popularity_cents
HAVING c.popularity_cents <> coalesce(sum(b.amount_cents), 0);

-- revenue today, by purpose
SELECT purpose, count(*), sum(amount_cents)/100.0 AS usd
FROM payment WHERE status = 'SETTLED' AND created_at >= date_trunc('day', now())
GROUP BY 1;

-- refunds and reversals as a share of settlement
SELECT status, count(*), sum(amount_cents)/100.0 AS usd
FROM payment WHERE created_at > now() - interval '7 days' GROUP BY 1;
```

⚠️ **`payment_event` is written for every webhook, including rejected and duplicate ones.**
A success-only record under-reports exactly when something is attacking the endpoint. A
climbing count of signature failures is the earliest signal that someone is probing for
failure 2 above.

## Product signals

| Signal | Query shape | Why it is the interesting one |
| --- | --- | --- |
| **Checkout → settle conversion** | settled payments ÷ checkouts created, per hour | *The single most valuable metric here.* A drop is failure 1 before anyone emails |
| Boost size distribution | percentiles of `amount_cents` over 24h | the outbid target is derived from the top; one enormous boost changes the product's economics for everyone |
| Unusual single boost | `amount_cents > boost.max.cents` | either the best day this product has had, or a compromised card. Both want a human |
| Pending submissions ageing | `listing_submission` `PENDING` older than 48h | failure 4 |
| Board staleness | time since the last settled boost, per tab | a category nobody boosts is a category to merge or drop |
| Leaderboard p95 | request timing on `/api/v1/leaderboard` | it is the only page most visitors see |

## Infrastructure signals

Alert when: the health endpoint is not healthy for **two consecutive checks** · cold starts
become frequent (the keep-alive has stopped) · Hikari active connections sit at
`BIDCELEB_DB_POOL_MAX` · the Supabase connection count approaches the project limit ·
database size crosses `watch.storage.budget.mb`.

## The alert lines

The service emits these at `WARN` when a limit is **approached**. Nothing scrapes this
service, so these lines *are* the monitoring, and a log-based alert on the host keys on the
prefix. Each carries `action=runbook:<procedure>` and the current value against its
threshold.

| Line | Meaning | Procedure |
| --- | --- | --- |
| `alert.settlementGap` | boosts created but unsettled beyond the threshold | *payments succeeded but popularity did not move* |
| `alert.ledgerDrift` | the board disagrees with the ledger | *popularity drift* |
| `alert.webhookRejected` | signature failures climbing | *a forged webhook* |
| `alert.storage` | database size nearing its budget | *the database is filling up* |
| `alert.submissionsAgeing` | paid submissions unreviewed | *the moderation queue has stalled* |

Thresholds are `watch.*` rows in `app_config` — change them without a deploy.
**`watch.enabled = false` silences all of them, which silences the *warning*, not the
limit.**

## Correlation ids

**Every log line carries a correlation id in brackets**, and every error response quotes
the same id in its body (`error.correlationId`). For a payment, the provider's event id is
the second id worth grepping — it is the only one that exists on both sides of the
boundary, and it is what makes a provider-side investigation match ours.

`LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs` turns these into JSON fields.

## Tracing one boost, end to end

1. `payment_event` — did the webhook arrive at all, and did its signature verify?
2. `payment` — did it settle, and for the right amount and purpose?
3. `boost` — is there a row, and is its status `SETTLED`?
4. `celebrity.popularity_cents` — did the trigger fire? Compare against the drift query.
5. The leaderboard response — is it a cache serving a stale ETag?

Steps 1–4 are the ledger; step 5 is presentation. **Fix a discrepancy in the direction
1 → 5, never the reverse.** Correcting the board without correcting the ledger produces a
number that is right until the next recomputation and wrong forever after.

## Silence is a failure mode

A board that was taking boosts hourly and now takes none is either a payment outage or a
product that has stopped mattering. Both are worth knowing on the day rather than in the
monthly numbers.
