---
title: Observability — what to watch, and how to trace one request
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Observability

⚠️ **This file and [runbook.md](runbook.md) are the two that must not be inherited with the
names swapped.** Every product fails silently in its own way, and these are where that
knowledge lives. A runbook copied unchanged from another project is worse than none: it
reads as authoritative while describing incidents that cannot happen here.

What follows is the *method*. The content is per project.

## Start by naming the silent failures

Ask one question: **what can go wrong here without producing a 500?**

Write the answers down first, before choosing a single metric. Every product has two or
three, they are specific to it, and they are the entire reason this file exists. Examples
of the *shape* of the answer:

- money moves in a direction nobody intended, slowly, and no request fails
- the system returns a confident, well-formed, **wrong** answer
- a background job stops running and the only symptom is data getting stale
- a limit is approached over days; the failure is instant when it arrives

Every one of those is invisible to an uptime monitor. That is the point.

## Then classify the signals

| Class | Question it answers | Where it usually lives |
| --- | --- | --- |
| **Money** | is spend or revenue behaving as intended? | a per-transaction ledger table, written **whether the operation succeeded or not** |
| **Product** | is the thing the product promises actually happening? | domain tables — this is the class most often missing |
| **Infrastructure** | is the service up, and near a limit? | health endpoint, connection pool, host dashboard |

⚠️ **A success-only ledger under-reports exactly when things are going wrong.** Record
failed and refused operations too, with their cost — a retry loop that fails is still
billed, and it is the failure mode most likely to run away.

## Alert on approach, not on arrival

The service should emit a `WARN` line when a limit is being *approached*, carrying:

- a stable prefix per condition (`alert.<condition>`) that a log-based alert can key on
- the current value and the threshold
- `action=runbook:<procedure>` naming the procedure that handles it

Thresholds belong in **database rows**, so they change without a deploy. Give the whole set
a single off switch, and write down what it means: **silencing the warning does not raise
the limit.**

## Correlation ids are not optional

**Every log line carries a correlation id**, and every error response quotes the same id in
its body. One grep then reconstructs a whole request. Without it, a user report ("it was
broken around 3pm") is unanswerable at any volume above trivial.

For background work, the job's own id plays the same role.

Structured console logging (JSON with the diagnostic context as fields) costs one setting
and makes the difference between grepping and querying.

## Silence is a failure mode

A component that goes from steady traffic to zero is worth surfacing. Most monitoring only
notices *too much*; the interesting failure is often *nothing at all*.

## The end-to-end trace

Write the ordered steps for your product: from the log line, to the record that decided the
behaviour, to the configuration that shaped it. Four or five steps, each a query someone
can paste. A trace nobody has walked through is a trace that will not work at 2am.

## What is deliberately not here

No metrics backend, no tracing backend, no log aggregation. At one instance, the host's log
tail plus the database is enough, and every one of those tools is another free tier to stay
inside. Revisit when there is more than one instance, or when someone other than you is
on call.
