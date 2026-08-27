---
title: Secrets — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Secrets

## The inventory, in full

| Secret | Lives in | Reachable by the app? | Blast radius if leaked |
| --- | --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | GitHub Actions secret | **no** | someone can deploy arbitrary code to your Worker |

That is the list. One credential, held by CI, never read at runtime.

## The top-tier credential

`CLOUDFLARE_API_TOKEN` is the only thing here worth stealing, and it is worth stealing
properly: it publishes code to the origin players load. A leak is not a data breach — there
is no data — it is a **supply-chain** problem, because the attacker gets to serve their
JavaScript from your domain to your players.

Consequences that follow from that:

- **Scope it to Workers only.** Use Cloudflare's "Edit Cloudflare Workers" template. A
  global API key would also carry DNS and every other zone setting.
- **It never touches a laptop.** Local development needs no token at all; `wrangler dev`
  runs the whole stack, Durable Objects included, on your machine. A token on a laptop is
  a token in a shell history, a backup and a crash report.
- **Rotate on any doubt.** It costs a minute and there is no downtime: create the new
  token, update the GitHub secret, delete the old one, re-run the last deploy.

## Things that look secret and are not

| Value | Why it is safe in the open |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | an identifier, not an authenticator. It appears in wrangler output and dashboard URLs |
| The room code | five characters, and knowing one only lets you *join a lobby* — which is the entire point of an invite link |
| A player's seat token | scoped to one room, held in `sessionStorage`, worthless once the room expires |

⚠️ **The seat token is the one to think twice about.** It is what lets a refreshed tab
reclaim its seat, so it is a bearer credential for that seat. It is deliberately kept in
`sessionStorage` rather than `localStorage`, because localStorage is shared across every
tab on the origin and a second tab would silently take the first one's seat. It is never
logged, never in a URL, and dies with the room.

## What there is no secret for

No database password, no signing key, no OAuth client secret, no model-provider key. If a
change is about to introduce one, that is a design change worth stating out loud in
`global-context/shared/decisions.md` — not a config change.

## Rotating

```
Cloudflare → My Profile → API Tokens → create a replacement (Edit Cloudflare Workers)
GitHub → repo → Settings → Secrets and variables → Actions → update CLOUDFLARE_API_TOKEN
re-run the most recent deploy workflow      ← proves the new token works
Cloudflare → delete the old token           ← only after the green run
```

Deleting first and testing second is how you find out the new token had the wrong scope
while the site is undeployable.
