---
title: Members & Roles
summary: "Invite people into a workspace, assign roles, and bill the right way for over-quota seats on the Team plan."
eyebrow: teams
last_updated: 2026-05-29
---

# Members & Roles

Wokku organises apps and resources into [workspaces](/docs/workspaces/personal-vs-org). Every user has one **personal workspace** (your free account) and can be a member of any number of **org workspaces** (the Team plan).

This page covers managing the members of a workspace — inviting, assigning roles, removing, and how Team seat billing works.

## Inviting a member

Open the workspace at `/dashboard/workspaces/<id>` (or use the [switcher](/docs/workspaces/switching) to jump in first). Admins see the **+ add member** form:

1. Type the person's email address.
2. Pick a role: viewer / member / admin.
3. Submit.

**The person must already have a Wokku account** — we don't email signup invitations yet. Ask them to sign up at [wokku.cloud](https://wokku.cloud) with the same email, then retry the add.

```text
> No user with that email — ask them to sign up first.
```

That's the error you'll see if the email doesn't match an existing account.

## Roles

| Role | What they can do |
|---|---|
| **Viewer** | Read-only access to apps, logs, metrics, and the audit log. Useful for stakeholders, designers, BizOps. |
| **Member** | Everything Viewer can, plus deploys, env vars, custom domains, database management, and addon CRUD. |
| **Admin** | Everything Member can, plus inviting / removing members, changing roles, and switching the plan. The workspace **owner** is always admin and can't be demoted. |

Role changes take effect on the member's next request — no reauth needed.

## Removing a member

In the workspace's members table, click **remove** on the row. The person loses access to the workspace immediately:

— Apps they deployed stay (the workspace owns the apps, not the member)
— API tokens they created against the workspace get revoked on the next call
— Their personal workspace is unaffected

The workspace **owner** can't be removed — to transfer a workspace to someone else, contact support.

## Seat billing (Team plan only)

The Team plan includes **3 seats** in the price (Rp 750.000 / month). Additional seats are billed at **Rp 45.000 each / month**.

How it works:

— You can add as many members as you want — there's no hard cap on Team
— The dashboard shows a banner when the member count exceeds the included seats
— On your next invoice, the overage is added automatically: `extra_seats × Rp 45.000`
— Removing a member before the billing date drops them from the next invoice — proration is by *count at invoice time*, not by hours-in-workspace

> The other paid plans (Solo, Pro) hard-cap at 1 seat — you can't invite a second member without upgrading to Team.

## What members see

A member of an org workspace gets the [workspace switcher](/docs/workspaces/switching) at the top of their dashboard. They can switch between their personal workspace and any orgs they belong to; data is scoped per workspace.

A workspace switch:

— Changes which apps and resources show in the dashboard
— Changes who pays for new resources (the workspace owner, not the member)
— Doesn't change the member's own auth / 2FA / API token

## CLI

```bash
wokku members:add alice@example.com --workspace acme-co --role member
wokku members:remove alice@example.com --workspace acme-co
wokku members:list --workspace acme-co
```

The CLI uses the same email-must-exist rule.

## API

```bash
curl -X POST https://wokku.cloud/api/v1/workspaces/WORKSPACE_ID/members \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"email": "alice@example.com", "role": "member"}'
```

See [API reference](/docs/api/endpoints) for the full schema.

## Audit log

Every add / remove / role change shows up in the workspace [audit log](/docs/monitoring/audit-log) with the actor, the target, and the role. Useful for compliance and for noticing the "who removed Alice?" question after the fact.

## See also

— [Permissions](/docs/teams/permissions) — what each role can do, in detail
— [Personal vs Org workspaces](/docs/workspaces/personal-vs-org) — when to create an org workspace
— [Switching workspaces](/docs/workspaces/switching) — how the topbar switcher works
