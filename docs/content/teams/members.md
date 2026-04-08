# Members & Roles

Invite team members and assign roles.

## Invite a Member

:::tabs
::web-ui
Go to **Teams** → select your team → **Invite Member**. Enter their email and select a role.

::cli
```bash
wokku members:add --team engineering --email alice@example.com --role admin
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/teams/TEAM_ID/members \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"email": "alice@example.com", "role": "admin"}'
```

::mcp
Ask Claude: *"Invite alice@example.com to the engineering team as admin"*

::mobile
Tap **Teams** → your team → **Invite**.
:::

## Roles

| Role | Description |
|------|-------------|
| **Viewer** | Read-only access to apps, logs, and metrics |
| **Member** | Deploy, manage config, domains, and databases |
| **Admin** | Full access including server and team management |

See [Permissions](/docs/teams/permissions) for detailed permissions per role.

## Remove a Member

:::tabs
::web-ui
Go to **Teams** → your team → click **Remove** next to the member.

::cli
```bash
wokku members:remove --team engineering --member MEMBER_ID
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/teams/TEAM_ID/members/MEMBER_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Remove member MEMBER_ID from engineering team"*

::mobile
Tap Teams → your team → swipe on member to remove.
:::
