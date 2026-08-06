---
title: Switching Workspaces
summary: "The topbar switcher is how you move between your personal workspace and the orgs you belong to. Session-cookie persisted, deep-link friendly."
eyebrow: workspaces
last_updated: 2026-05-29
---

# Switching Workspaces

When you're a member of more than one workspace — your personal plus any orgs you've created or joined — the **workspace switcher** at the top-left of every dashboard page is how you move between them.

## The switcher

It lives right after the Wokku logo in the topbar. Clicking it opens a dropdown:

— **Current workspace** highlighted at the top
— **Other workspaces you belong to** listed below — click one to switch
— **+ new workspace** at the bottom — creates an org workspace (paid plans only)
— **manage →** link to `/dashboard/workspaces` (full list with per-workspace actions)

The dropdown shows up to 8 workspaces inline; anything beyond is reachable via `manage →`.

## How "current" is decided

The current workspace is resolved per-request in this order:

1. **Explicit session cookie** — `session[:current_team_id]` set by the most recent switch
2. **Your personal workspace** — fallback when no session cookie

So once you switch, the choice sticks across page loads (and tabs, browsers, etc. that share the session) until you switch again.

## Deep-linking

Sometimes you want to share a dashboard URL that lands the recipient in a *specific* workspace, not their default. The switcher action — the URL pattern `POST /dashboard/workspaces/<id>/switch` — accepts a `return_to` param:

```text
POST /dashboard/workspaces/abc123/switch?return_to=/dashboard/apps/myapp
```

After switching, the user is redirected to `return_to`. Membership is re-validated server-side, so if the recipient isn't a member of that workspace, the switch fails with 404 and they stay in their previous workspace.

## What scope changes when you switch

Everything in the dashboard re-renders for the new workspace:

— **Apps list** — shows the apps in the new workspace
— **Databases, caches, object storage** — same scope
— **Billing & invoices** — switches to the new workspace's plan and bill history
— **Audit log** — shows the new workspace's events
— **Team / members page** — the new workspace's members

What stays the same:

— **Your account** — login, 2FA, OAuth providers
— **Your CLI / API tokens** — same tokens, they operate on whichever workspace is active
— **Your profile** — name, email, avatar, notifications preference

## From the CLI

```bash
wokku workspaces:list             # show workspaces you belong to
wokku workspaces:switch <slug>    # switch context
wokku workspaces:current          # print active workspace
```

Once switched, every other CLI command (`wokku deploy`, `wokku logs`, `wokku databases:list`) operates against that workspace.

## From the API

API tokens are user-scoped. Add `X-Wokku-Workspace: <slug>` to scope a request to a specific workspace:

```bash
curl https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Wokku-Workspace: acme-co"
```

Without the header, the API defaults to your personal workspace.

## When the switcher doesn't show up

If you're only in one workspace (the common case for a new account), the switcher renders but as a static label — there's nothing to switch to. Once you create an org workspace or get invited to one, the dropdown lights up.

## Common gotchas

— **"I deployed to the wrong workspace"** — switch contexts and use [app transfer](/docs/apps/lifecycle) to move it
— **"My CLI keeps using the wrong workspace"** — `wokku workspaces:switch <slug>` persists in `~/.wokku/config`; check `wokku workspaces:current`
— **"The session reset and I'm back in personal"** — cookie expired or the browser cleared it; just switch again

## See also

— [Personal vs Org workspaces](/docs/workspaces/personal-vs-org) — when to create org workspaces
— [Members & Roles](/docs/teams/members) — managing who's in a workspace
