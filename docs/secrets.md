---
title: Secrets — bidceleb
status: current
last_updated: 2026-08-26
applies_to: [bidceleb-backend, bidceleb-frontend, dev-ops]
---

# Secrets — bidceleb

The policy, the two stores, the rotation pattern and the leak procedure are canonical on
`main`. This file records what is specific to this product.

## The top-tier credential

> **`BIDCELEB_PAYMENT_WEBHOOK_SECRET`.**

Popularity — the entire product — is minted by exactly one code path: a webhook whose
signature verifies. Whoever holds that secret can forge settlements and award unlimited
popularity **without paying a cent**, and the fraud does not appear in the payment
provider's dashboard because no payment ever existed.

That makes it worse than the database password. A leaked database password exposes *data*,
which is bad and recoverable. A leaked webhook secret corrupts *the board*, which is the
only thing anyone is buying, and every affected boost has to be found by reconciling
against the provider's records rather than our own — because our own is what the attacker
wrote.

Handling that follows from this and not from habit:

- rotate it on **suspicion**, not on evidence; the cost of an unnecessary rotation is one
  service restart
- never use the production endpoint secret locally, not even briefly — use the provider's
  test-mode endpoint, which has its own
- treat a rising count of signature failures as an incident in progress, not as noise

## Classification

| Value | Secret? | Why |
| --- | --- | --- |
| `BIDCELEB_PAYMENT_WEBHOOK_SECRET` | ✅ **top-tier** | forging it mints popularity for free |
| `BIDCELEB_PAYMENT_API_KEY` | ✅ | initiates charges and issues refunds against real money |
| `BIDCELEB_DB_PASSWORD` | ✅ | full read/write over the boost ledger |
| `BIDCELEB_DB_URL`, `BIDCELEB_DB_USERNAME` | 🟡 | not dangerous alone, but they name the target — keep them beside the password |
| `BIDCELEB_FIREBASE_PROJECT_ID` | ❌ | ID tokens are verified against Google's published JWK set; it is visible in any web client's config |
| `NEXT_PUBLIC_*` | ❌ | **published to every visitor by definition** |
| `BIDCELEB_PUBLIC_BASE_URL`, `_PORT`, `_LOG_LEVEL` | ❌ | plain configuration |

**There is no Firebase service-account key anywhere in this system.** If a guide tells you
to download `firebase-adminsdk-*.json`, it does not apply here.

## Why the provider's key is in an env var and its config is in a table

`payment_provider_config` holds the base URL, the display name and the **name** of the
environment variable that holds the key — never the key. Two consequences worth stating
because both get undone by well-meaning refactors:

1. **Switching provider is an `UPDATE`, not a release.** That matters here specifically:
   the provider is an open decision (cross-border USD collection is the constraint, not the
   API), and the choice may change after launch.
2. **A database backup is never a credential leak.** Anyone can read that table.

## Local development

The test suite needs **no credentials at all** — it starts its own Postgres and uses the
`STUB` payment adapter, which settles synchronously. That is deliberate: it is what lets CI
run on a fork's pull request, and what makes "production credentials never land on a
laptop" affordable rather than aspirational.

When you need to exercise a real provider locally, use its **test mode** — a separate key
and a separate webhook secret, both of which move only test money.

⚠️ **Never point local development at the production database.** The boost ledger is
financial; a local process with production credentials can corrupt it as easily as read it,
and the credential is then in your shell history, your IDE run configuration and any crash
dump.

## Rotation

| Secret | How | Downtime |
| --- | --- | --- |
| `BIDCELEB_PAYMENT_WEBHOOK_SECRET` | most providers allow two live endpoint secrets during a roll — add the new endpoint, verify a test event, remove the old. If yours allows only one, accept a short window and **replay any events from it afterwards** | brief or none |
| `BIDCELEB_PAYMENT_API_KEY` | create a second key → update Render → save (restarts) → verify one test checkout → revoke the first | none |
| `BIDCELEB_DB_PASSWORD` | Supabase → Settings → Database → Reset password → update Render → save. **Brief downtime** — Supabase free has one database user, so old and new cannot coexist. Accepted risk, recorded in `platform-security.md` | brief |
| `BIDCELEB_FIREBASE_PROJECT_ID` | not a secret; changing it means moving Firebase projects, not rotating | — |

⚠️ **After rotating the webhook secret, check for events that failed to verify during the
window** and replay them. Otherwise the rotation itself creates the "paid but popularity did
not move" incident — see [runbook.md](runbook.md).

## If money is involved

Rotate first, investigate second, as always. Then reconcile — and reconcile **against the
provider's record of charges, not ours**. During any incident where settlement integrity is
in question, our own ledger is evidence of what happened, not proof of what should have.
