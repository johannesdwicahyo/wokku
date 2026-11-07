---
title: Audit Log
summary: See who did what in your workspace, from where and when — filter it, export it as CSV, or read it from the CLI and API.
last_updated: 2026-11-07
---

You'll look up actions taken in your workspace — deploys, config changes, domains, databases, members, billing. Open **Activity** in the sidebar.

## What each entry shows

| Field | Example |
|---|---|
| **When** | Timestamp to the second |
| **Who** | The member, or the system for automatic actions |
| **Action** | `app.deployed`, `config.updated`, `app.renamed` |
| **Target** | The app, database or member acted on |
| **Channel** | Dashboard, CLI, API, MCP, git push or Webhook |

## Filter and export

On the **Activity** page, filter by **Action**, **Channel**, **User**, **Since** and **Until**. Filters combine, and the URL keeps them, so you can share a filtered view.

Click **Export CSV** to download the filtered entries. Columns:

```text
created_at, user_email, action, target_type, target_name, channel, metadata_json
```

## Tamper evidence

Each night Wokku seals the day's entries into a hash chain. The **verified** banner on the page shows the last sealed day, its entry count and the start of the chain hash. It proves the entries you see haven't been edited since they were sealed.

## CLI and API

:::tabs
::cli
```bash
wokku activity   # last 20 entries
```

::api
```bash
curl "https://wokku.cloud/api/v1/activities?limit=100" \
  -H "Authorization: Bearer $TOKEN"
```

Returns the newest entries first. `limit` is 1–200 (default 50); there are no other filters — use the dashboard for filtering.

::mcp
Ask Claude: *"What changed in my workspace today?"*
:::

## See also

- [Logs](/docs/monitoring/logs) — your app's own output
- [Members & Roles](/docs/teams/members)
