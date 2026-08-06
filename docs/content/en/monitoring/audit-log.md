---
title: Audit Log
summary: "Who did what, from where, when. Every plan ships with an audit log — Free included. Filter, export CSV, tamper-evidence via daily digest chain."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Audit Log

The audit log records **every meaningful action** taken in a workspace — app created, config changed, deploy started, member added, plan switched — with the actor, the target, and the channel (Dashboard / CLI / API / MCP / git push / webhook).

Available on **every plan, including Free**. Find it at `/dashboard/activities` or via the workspace's sidebar.

## What gets recorded

Every record has:

— **Actor** — the user who did it (or system, for jobs like daily-debit)
— **Action** — namespaced like `app.deployed`, `config.updated`, `team.member_added`
— **Target** — what was acted on (app name, database name, etc.)
— **Channel** — Dashboard / CLI / API / MCP / git_push / webhook
— **Timestamp** — to the second
— **Metadata** — JSON blob with action-specific context

The full list of action codes is in `Activity::ACTIONS` — covers app lifecycle, config, domains, SSH keys, databases, servers, backups, GitHub integration, templates, notifications, team membership, and billing events.

## Filtering

The page accepts five filter dropdowns:

— **Action** — every distinct action namespace, alphabetical
— **Channel** — Dashboard / CLI / API / MCP / git push / Webhook
— **User** — any member of the workspace
— **Since** — date input (start of day)
— **Until** — date input (end of day)

All filters AND together. The URL params survive a refresh so the filtered view is shareable.

## CSV export

Use the **export CSV** link in the top-right of the audit log to download the filtered set. Columns:

```text
created_at, user_email, action, target_type, target_name, channel, metadata_json
```

Useful for compliance reports, attaching to a security incident postmortem, or bulk-grep workflows.

## Tamper evidence

Every night, an `ActivityDigest` job hashes the day's activities into a chain (`chain_hash = SHA256(prev_hash || min_id || max_id || row_count || row_hashes)`) and persists one row per day. The audit log page surfaces a green **verified** banner showing the latest digest's date, row count, and the leading 16 chars of the chain hash:

```text
[verified] // chain hash verified through 2026-05-28 · 1,247 rows · hash a3f4b8…
```

If the digest job hasn't run yet (fresh install), you get the pending banner instead:

```text
// digest chain not yet built — ActivityDigestJob runs nightly
```

The chain doesn't prove rows aren't *missing* from earlier digests; it proves the **rows you can see haven't been altered** since the digest landed. To audit for missing rows, compare consecutive digest `row_count` totals against your expected baseline.

## Channel pills

Each record shows a small pill indicating where the action came from:

— **Dashboard** — browser session
— **API** — REST API token call
— **CLI** — `wokku <cmd>` command
— **MCP** — Claude Code plugin invocation
— **git push** — deploy-via-push hook
— **Webhook** — GitHub auto-deploy or other webhook

Useful for narrowing "what did the `terraform-bot` API token do today" or "what did anyone do via the CLI last week".

## API

```bash
curl https://wokku.cloud/api/v1/activities \
  -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode "action_eq=app.deployed" \
     --data-urlencode "since=2026-05-01"
```

Returns the same JSON shape the dashboard renders.

## Retention

Audit log retention is **unlimited** — we never auto-delete records. The audit log is small (tens of kilobytes per workspace per month), and the value of retroactive auditing far exceeds the storage cost.

If you need to purge for a compliance reason (GDPR right-to-be-forgotten on a removed member), email [support@wokku.cloud](mailto:support@wokku.cloud).

## Self-hosted

Community Edition includes the audit log table + page. The `ActivityDigestJob` requires the recurring-jobs config in `config/recurring.yml`; otherwise the chain doesn't build automatically.

## See also

— [Logs](/docs/monitoring/logs) — runtime container logs (different surface)
— [Members & Roles](/docs/teams/members) — workspace membership events show up here
