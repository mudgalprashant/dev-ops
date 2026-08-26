---
title: Runbook — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend]
---

# Runbook — bidceleb

Every procedure assumes you can reach the Supabase SQL editor and the Render dashboard.
**Most controls are database rows, deliberately, so you can act without waiting for a
build.** The universal procedures (credential leak, connection exhaustion, first deploy,
rollback) are canonical on `main`; this file covers what is specific to this product.

Ownership: money and integrity → here. "The board renders oddly" →
[observability.md](observability.md). A schema or domain bug →
`global-context/bidceleb-backend-context/playbooks/debug-failure.md`.

---

## Severity 1 — popularity is being minted without payment

The product is the board being true. This is the only incident that attacks that directly.

**How you know:** `alert.webhookRejected` climbing, or settled boosts with no matching
charge at the provider.

1. **Stop the bleeding first.** Rotate the webhook signing secret at the provider and in
   Render, in that order. A forged-webhook attack ends the moment the old secret stops
   verifying; every other step can wait.
2. **Verify the rotation took**, rather than assuming — a saved Render variable restarts
   the service, and a restart that failed leaves the old value running:
   ```sql
   SELECT provider_event_id, received_at, signature_valid
   FROM payment_event ORDER BY received_at DESC LIMIT 20;
   ```
3. **Find the forged settlements.** Reconcile against the **provider's** record of charges,
   never our own — our own is what the attacker wrote:
   ```sql
   SELECT b.id, b.celebrity_id, b.amount_cents, p.provider_ref, b.settled_at
   FROM boost b JOIN payment p ON p.id = b.payment_id
   WHERE b.status = 'SETTLED' AND b.settled_at > now() - interval '24 hours'
   ORDER BY b.amount_cents DESC;
   ```
   Export the provider's charges for the same window and diff on `provider_ref`.
4. **Reverse them as events, never as an `UPDATE`.** Insert the reversing rows so the
   trigger moves `popularity_cents` and the ledger still reconciles afterwards. A manual
   `UPDATE celebrity SET popularity_cents = …` fixes the display and breaks the invariant,
   and the next drift check will "find" your correction as the bug.
5. Only then work out how the secret leaked. **Rotate first, investigate second.**

---

## Severity 1 — payments succeeded but popularity did not move

People have paid and the board is unchanged. Every minute here is a refund request and a
public accusation.

**How you know:** `alert.settlementGap`, or a support message with a receipt attached.

1. Establish which side is broken — ours or the delivery:
   ```sql
   SELECT count(*) FROM payment_event WHERE received_at > now() - interval '1 hour';
   SELECT status, count(*) FROM boost WHERE created_at > now() - interval '1 hour' GROUP BY 1;
   ```
   Events arriving but boosts stuck `PENDING` → our handler. **No events at all** → the
   provider cannot reach us; check the endpoint URL registered at the provider, then that
   the service is up rather than cold-starting.
2. **Replay from the provider's dashboard.** The handler is idempotent on
   `(provider, provider_event_id)`, so replaying the whole window is safe and is almost
   always the fix. Replay everything since the gap opened; do not hand-pick.
3. If the handler itself is failing, grep its correlation id and read the actual exception.
   A common cause is a schema change deployed ahead of the code that writes it.
4. **Do not settle by hand while the cause is unknown.** A manual settlement plus a
   successful replay produces a double boost, and the user who was under-credited is now
   over-credited — which nobody reports.
5. Resume, then confirm the gap closed with the settlement-gap query in
   [observability.md](observability.md).

⚠️ **Never settle a boost from the browser's success redirect,** however tempting it is
during this incident. The redirect is a hint that the user came back, not evidence that
money moved; anyone can visit it.

---

## Severity 2 — the board disagrees with the ledger

**How you know:** `alert.ledgerDrift`, or the reconciliation query in
[observability.md](observability.md) returning rows.

1. Take the drift query's output and look at *direction*: board above ledger means
   something incremented without a boost row; board below means a settlement did not
   propagate.
2. Suspect, in order: a direct SQL write that bypassed the trigger (the usual cause), a
   refund applied without a reversing event, a migration that rebuilt the table without
   restoring the trigger.
3. Recompute from the ledger, because **the ledger is the source of truth and the counter
   is a cache of it**:
   ```sql
   UPDATE celebrity c
   SET popularity_cents = x.total, boost_count = x.n
   FROM (
     SELECT celebrity_id, coalesce(sum(amount_cents), 0) AS total, count(*) AS n
     FROM boost WHERE status = 'SETTLED' GROUP BY celebrity_id
   ) x
   WHERE x.celebrity_id = c.id AND c.popularity_cents <> x.total;
   ```
4. Confirm the trigger still exists before declaring it fixed. Recomputing without
   restoring the trigger means being back here tomorrow.

---

## Severity 2 — a chargeback, or a fraudulent boost

1. Reverse it as an event (a `REFUNDED` boost row), never by editing the counter.
2. Leave the original rows in place. **The boost ledger is financial: revoke, never
   delete.** Log rows and disputes reference those ids.
3. If one payer accounts for several, check whether the card is being tested against us —
   a run of small boosts from one source is card-testing, not enthusiasm.

## Severity 2 — the payment provider is down

1. `UPDATE app_config SET value = 'false' WHERE key = 'payments.enabled';`
2. **This stops taking money. It never stops serving the board.** The leaderboard, the
   tabs and every celebrity page keep working; the Boost button shows a maintenance state.
   If the board goes down when this flips, that is a bug — fix it before the next outage,
   because a kill switch people hesitate to use is not a kill switch.
3. Verify no new checkouts are being created, then re-enable and confirm one test boost
   settles end to end before announcing anything.

## Severity 3 — the moderation queue has stalled

```sql
SELECT id, proposed_name, created_at, now() - created_at AS waiting
FROM listing_submission WHERE status = 'PENDING' ORDER BY created_at;
```
Each row is someone who paid $100 and is waiting. **Refund rather than let one age past a
week** — a slow approval is a bad experience, an ignored payment is a chargeback and a
public complaint.

## Severity 3 — a takedown request about a listed person

1. `UPDATE celebrity SET status = 'HIDDEN' WHERE slug = :slug;` — it leaves the board
   immediately.
2. **Never hard-delete.** The boost rows are financial records and must survive; a delete
   also silently destroys the evidence you would need if the request is contested.
3. Record who asked and on what basis. Then decide, unhurried, whether it comes back.

## The database is filling up

The universal procedure on `main` applies. Here the growing table is almost always
`payment_event`, which stores raw webhook payloads. **Its purge job is part of the payments
slice, not a follow-up** — retention with no job behind it is decorative. Keep enough
history to reconcile a dispute (90 days is the usual chargeback window), delete in batches,
then `VACUUM`.

## A traffic spike

The board is read-heavy and public; the reclaim loop means a spike arrives all at once from
one social post. In order: confirm the leaderboard is being served from cache (ETag hit
rate), confirm the pool is not exhausted, and only then consider the host's paid instance.
**Do not raise `BIDCELEB_DB_POOL_MAX` to cope with a spike** — exhausting the shared
Supabase pooler takes out the SQL editor you would use to diagnose it.
