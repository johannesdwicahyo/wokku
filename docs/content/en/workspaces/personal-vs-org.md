---
title: Workspaces
summary: Your personal workspace, org workspaces for shared work, and how to switch between them.
last_updated: 2026-11-07
---

Everything you create on Wokku — apps, databases, domains, the audit log — belongs to a **workspace**. This page shows the two kinds and how to move between them.

## Personal and org workspaces

| | Personal | Org |
|---|---|---|
| Who gets one | Every account, at sign-up | Created by you when you need it |
| Members | Only you | You plus anyone you add |
| Can be left or deleted | No — it's tied to your account | You're the owner; the owner can't be removed |
| How many | One | As many as you like |

Use your personal workspace for your own projects. Create an org workspace for work you share — a startup, a client, a co-founder.

## Switch workspaces

The workspace switcher is at the top of the sidebar.

1. Click the workspace name.
2. Pick another workspace from the list.

The dashboard reloads with that workspace's apps, databases, billing and audit log. The choice sticks until you switch again. Your login, 2FA, profile, SSH keys and API tokens stay the same in every workspace.

**Manage →** in the switcher opens the full list of workspaces you belong to.

## Create an org workspace

1. Open the sidebar switcher → **+ New workspace**.
2. Enter a name (names are unique across Wokku).
3. Pick a plan and confirm.

You're switched into the new workspace straight away, as its owner and an admin.

:::callout note
The create form only offers **Solo**, **Pro** or **Team**. The plan you pick sets how many members the workspace can hold: Team has no member cap, Solo and Pro hold one. The workspace page shows seats used and included.
:::

## Who pays

Each workspace is its own billing boundary. Resources created inside an org workspace are billed to that workspace, not to the member who created them. See [Pricing](/docs/billing/pricing).

## CLI, API and MCP

Tokens belong to you, not to a workspace. Listing commands (`wokku apps`, `GET /api/v1/apps`) return everything you can access across all your workspaces.

Creating an app from the CLI, API or MCP puts it in your default workspace — you can't pick an org workspace from them yet. To create an app in an org workspace, switch to it in the dashboard and create the app there.

`wokku teams` lists the workspaces you belong to, with their IDs.

## See also

- [Members & Roles](/docs/teams/members) — add people and set what they can do
- [Audit log](/docs/monitoring/audit-log) — what happened in a workspace
