---
title: Environment matrix — Cellbreak
status: current
last_updated: 2026-08-27
applies_to: [cellbreak]
---

# Environment matrix

## Runtime: empty, on purpose

**The Worker reads no environment variables.** There is no row to fill in because there is
nothing to configure: no database, no identity provider, no third-party API, no per-
environment origin. A room is a Durable Object; the client is static files served by the
same Worker.

What would be env vars in another project are **bindings**, declared in
`apps/server/wrangler.jsonc` and resolved by the platform:

| Binding | Kind | What it is |
| --- | --- | --- |
| `ROOMS` | Durable Object namespace | one object per room code; `RoomDO` |
| `ASSETS` | static assets | the built client, `apps/web/dist` |

Bindings are not secrets and are not per-environment. They are in the repo, in version
control, and they are supposed to be.

## CI: two values, neither read by the app

| Name | Where it lives | Secret? | Verify |
| --- | --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | GitHub → repo → Secrets → Actions | **yes** | a deploy run reaches "Uploaded" rather than 403 |
| `CLOUDFLARE_ACCOUNT_ID` | same | no — it is an identifier | wrangler resolves the account without prompting |

Both exist so `wrangler deploy` can publish from CI. Neither is available to the running
Worker, and neither belongs in a `.env` on a laptop. Rotation and scope:
[secrets.md](secrets.md).

## Local development

Nothing to set. The two commands that matter:

```bash
pnpm --filter @cellbreak/web dev       # client alone, on :5173, no Worker
pnpm --filter @cellbreak/server dev    # Worker + Durable Objects + built client, on :8788
```

⚠️ **`wrangler dev` serves the client from `apps/web/dist`, not from source.** Online
changes to client code do not appear until you re-run `pnpm --filter @cellbreak/web build`.
This is the single most common "my change did nothing" in this repo. The Vite dev server
has the opposite problem: hot reload works, but there is no `/api`, so online play is
unavailable there.

## The rule if a variable ever appears

The first one sets the pattern for every one after it. Before adding it:

1. Does it belong in `wrangler.jsonc` as a binding or a `var` instead? Most things do.
2. Is it secret, or does it merely look it? See [secrets.md](secrets.md) — the distinction
   decides whether it can be committed.
3. Does it differ between local and production? If not, it is a constant in the source,
   not configuration. A "configurable" value with one possible value is a place for a
   future outage to hide.
