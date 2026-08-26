---
title: Environment matrix
status: current
last_updated: 2026-08-26
applies_to: [every repo in every project]
---

# Environment matrix

**Names only — never a value, in this file or any other.** The authority for what an
application actually reads is its own configuration file and its `render.yaml`; this doc
exists so a human can see the whole contract in one place.

## The three rules

1. **Never a value in this repo**, including a placeholder that looks real. Use
   `CHANGE_ME_LOCAL_ONLY`. A realistic-looking fake gets copied into production by someone
   in a hurry.
2. **The app fails to start when a required variable is missing — never a silent default.**
   A silent default is how a production outage starts: the service comes up healthy and
   points at the wrong thing.
3. **Anything governing spend, pricing or a limit belongs in a database row, not an
   environment variable**, so it can be changed during an incident without a deploy.

## Naming

`<PROJECT>_<AREA>_<THING>` — one prefix per project, so `printenv | grep <PROJECT>_` shows
the entire contract. Deploy-related secrets are named after the **role**, not the vendor
(`DEPLOY_SSH_KEY`, not `ACME_SSH_KEY`): hosts get changed, and a vendor name in a secret
name turns the next migration into a rename across three places.

## The table each project fills in

| Variable | local | test | prod | Secret | Purpose / how to verify |
| --- | --- | --- | --- | --- | --- |
| `<PROJECT>_PORT` | ✅ | | ✅ | ❌ | |
| `<PROJECT>_LOG_LEVEL` | ✅ | | ✅ | ❌ | |
| `<PROJECT>_PUBLIC_BASE_URL` | ✅ | | ✅ | ❌ | origin only, no trailing slash, no path |
| `<PROJECT>_DB_URL` | ✅ | | ✅ | 🟡 | |
| `<PROJECT>_DB_USERNAME` | ✅ | | ✅ | 🟡 | |
| `<PROJECT>_DB_PASSWORD` | ✅ | | ✅ | ✅ | |
| `<PROJECT>_DB_POOL_MAX` | ✅ | | ✅ | ❌ | sized against the **database's** limit, not expected load |

Add one row per variable. Every row needs a *how to verify* — a variable nobody can check
is a variable nobody can fix.

Mark each **Secret** column ✅ / 🟡 / ❌ using the classification in [secrets.md](secrets.md).

## Retired variables

Keep a **Retired — delete on sight** list at the bottom of the project's version of this
file. A variable that is no longer read but still set is an unused credential: it can only
ever be a liability, so delete it rather than rotating it. Retired names are also the ones
most likely to be re-added by an out-of-date guide.

---

## Postgres via a connection pooler — the three traps

These apply to any managed Postgres fronted by a pooler (Supabase/Supavisor and friends),
and each one fails confusingly:

1. **Direct connections are often IPv6-only** without a paid add-on. Most hosts have no
   IPv6 egress, and the error reads like a firewall problem.
2. **Transaction mode has no prepared statements.** ORMs and migration tools both need
   them. Same host, different port, completely different semantics.
3. **A migration tool's advisory lock is connection-scoped**, so transaction pooling can
   release it on a different backend than took it — producing a lock that appears held by
   nobody.

→ **Use session mode (port 5432), not transaction mode (6543), and not direct.**

⚠️ Managed providers hand you a **libpq** URL; a JVM application needs a **JDBC** one.
Prepend `jdbc:`, drop any embedded `user:password@`, and keep `?sslmode=require`:

```
✗ postgresql://user:password@host.pooler.example.com:5432/postgres
✓ jdbc:postgresql://host.pooler.example.com:5432/postgres?sslmode=require
```

The username usually carries the project reference (`postgres.<project-ref>`). If an
authentication error names the *bare* user rather than the qualified one, the password is
not the problem — the username never reached the app and a local default took over.

## Browser-visible variables

**INVARIANT: anything a build inlines into client code is public.** In Next.js that is the
`NEXT_PUBLIC_` prefix; every framework has an equivalent. Database credentials, provider
API keys and webhook signing secrets must never appear there. Assume anything on that list
is printed on a billboard.

## What CI needs

Usually nothing. Design the test suite to require **no credentials** — a suite that needs a
secret cannot run on a fork's pull request, and the workarounds for that are all worse than
the constraint. Where CI genuinely needs a value, it goes in a GitHub **Environment**, not
a repository secret ([secrets.md](secrets.md) Step 2).
