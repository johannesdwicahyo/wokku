---
title: Members & Roles
summary: Add people to an org workspace, choose their role, and see exactly what each role can do.
last_updated: 2026-11-07
---

Add a teammate to an org [workspace](/docs/workspaces/personal-vs-org), give them a role, and change or remove it later. Only admins can manage members.

## Add a member

The person needs a Wokku account first — invites aren't emailed. If the email doesn't match an account, you'll see *"No user with that email — ask them to sign up first."*

:::tabs
::web-ui
1. Switch to the org workspace, then open the switcher → **Manage →** and pick the workspace.
2. Under **add by email**, enter their email.
3. Pick a role — viewer, member or admin — and click **add member**.

::cli
```bash
wokku teams                       # find the workspace (team) ID
wokku teams:members:add TEAM_ID --email alice@example.com --role member
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/teams/TEAM_ID/members \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com", "role": "member"}'
```

Get `TEAM_ID` from `GET /api/v1/teams`.

::mcp
Ask Claude: *"Add alice@example.com to my team as a member."* (uses `wokku_add_team_member`)
:::

If the workspace has used all its seats, the add fails with a message telling you to move to the Team plan.

## Change a role or remove a member

:::tabs
::web-ui
In the members table, change the role from the dropdown, or click **remove**.

::cli
```bash
wokku teams:members TEAM_ID                                  # shows membership IDs
wokku teams:members:role TEAM_ID MEMBERSHIP_ID admin
wokku teams:members:remove TEAM_ID MEMBERSHIP_ID
```

::api
```bash
# change role
curl -X PATCH https://wokku.cloud/api/v1/teams/TEAM_ID/members/MEMBERSHIP_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" -d '{"role": "admin"}'

# remove
curl -X DELETE https://wokku.cloud/api/v1/teams/TEAM_ID/members/MEMBERSHIP_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

::mcp
Ask Claude: *"Make alice an admin"* or *"Remove alice from my team."* (uses `wokku_update_team_member` / `wokku_remove_team_member`)
:::

Rules:

- The workspace **owner** can't be removed.
- A workspace always keeps at least one admin — the last admin can't demote themselves.
- Removing someone doesn't remove their apps: apps belong to the workspace.
- Their personal workspace is unaffected.

## What each role can do

| Action | Viewer | Member | Admin |
|---|:-:|:-:|:-:|
| View apps, logs, metrics, config vars | ✓ | ✓ | ✓ |
| Create and deploy apps | — | ✓ | ✓ |
| Change config vars, domains, scaling | — | ✓ | ✓ |
| Restart, stop, start, roll back | — | ✓ | ✓ |
| Resize, restore or retry a database | — | ✓ | ✓ |
| Delete apps | — | — | ✓ |
| Delete databases | — | — | ✓ |
| Add, remove and change members | — | — | ✓ |

The person who created a database can always manage and delete it, whatever their role.

Members added or removed from the dashboard show up in the [audit log](/docs/monitoring/audit-log).
