---
title: Available Tools
summary: Every Wokku tool Claude Code can call, grouped by task.
eyebrow: claude code
last_updated: 2026-11-07
---

Look up what Claude can do on Wokku. You rarely call these by name — ask in plain language and Claude picks the tool. Tools that delete or overwrite data ask you to confirm first.

## Apps

| Tool | What it does |
|---|---|
| `wokku_list_apps` | List your apps |
| `wokku_get_app` | Show app details |
| `wokku_create_app` | Create an app |
| `wokku_update_app` | Change app settings (name, deploy branch) |
| `wokku_rename_app` | Rename an app (its wokku.app address changes) |
| `wokku_clone_app` | Copy an app's settings into a new app (no env vars or data) |
| `wokku_lock_app` | Block new deploys |
| `wokku_unlock_app` | Allow deploys again |
| `wokku_delete_app` | Delete an app |
| `wokku_transfer_app` | Offer an app to another user by email |
| `wokku_list_transfers` | List incoming and outgoing transfers |
| `wokku_accept_transfer` | Accept a transfer |
| `wokku_decline_transfer` | Decline a transfer |
| `wokku_cancel_transfer` | Cancel a transfer you started |

## Deploys and releases

| Tool | What it does |
|---|---|
| `wokku_deploy_app` | Rebuild and deploy the latest code |
| `wokku_deploy_tarball` | Deploy a local folder without git push |
| `wokku_list_deploys` | List deploys |
| `wokku_get_deploy` | Show a deploy and its log |
| `wokku_ai_diagnose` | Ask AI why a deploy failed |
| `wokku_list_releases` | List releases |
| `wokku_get_release` | Show a release |
| `wokku_rollback` | Roll back to a release |

## GitHub and previews

| Tool | What it does |
|---|---|
| `wokku_list_github_repos` | List repos (or branches) the Wokku GitHub App can see |
| `wokku_github_connect` | Deploy on every push to a GitHub repo |
| `wokku_github_disconnect` | Disconnect the GitHub repo |
| `wokku_list_previews` | List pull-request preview apps |
| `wokku_set_preview_settings` | Turn previews on or off and pick their database |
| `wokku_destroy_preview` | Remove a preview app |

## Config

| Tool | What it does |
|---|---|
| `wokku_get_config` | Show environment variables |
| `wokku_set_config` | Set environment variables |
| `wokku_unset_config` | Remove environment variables |

## Running and scaling

| Tool | What it does |
|---|---|
| `wokku_restart_app` | Restart |
| `wokku_stop_app` | Stop |
| `wokku_start_app` | Start |
| `wokku_get_ps` | Show running processes |
| `wokku_scale_app` | Change how many of each process run |
| `wokku_get_dynos` | Show each process type's size and monthly cost |
| `wokku_list_box_sizes` | List sizes and prices |
| `wokku_resize_app` | Change a process type's CPU and RAM |
| `wokku_run_command` | Run a one-off command and wait for its output |
| `wokku_get_run` | Check a one-off run |
| `wokku_list_scheduled_tasks` | List scheduled tasks |
| `wokku_create_scheduled_task` | Add a scheduled task |
| `wokku_delete_scheduled_task` | Delete a scheduled task |

## Logs and monitoring

| Tool | What it does |
|---|---|
| `wokku_doctor` | Check your token, plugin version, host health and app state in one call |
| `wokku_get_logs` | Read logs |
| `wokku_get_app_metrics` | CPU and memory (last hour and last day) |
| `wokku_get_app_monitor` | Request totals and slowest URLs (last 24 h) |
| `wokku_get_app_vitals` | Core Web Vitals (last 7 days) |
| `wokku_rotate_vitals_token` | Issue a new web-vitals token |
| `wokku_list_incidents` | List outages (open by default) |
| `wokku_get_incident` | Show one incident |
| `wokku_list_alert_mutes` | List phone alert mutes |
| `wokku_mute_alerts` | Mute phone alerts for an app or event |
| `wokku_unmute_alerts` | Remove a mute |
| `wokku_list_notifications` | List notification channels |
| `wokku_create_notification` | Add a notification channel |
| `wokku_test_notification` | Send a test message |
| `wokku_delete_notification` | Delete a notification channel |
| `wokku_list_activities` | Recent activity |

## Domains and HTTPS

| Tool | What it does |
|---|---|
| `wokku_list_domains` | List domains |
| `wokku_add_domain` | Add a custom domain |
| `wokku_remove_domain` | Remove a domain |
| `wokku_enable_ssl` | Issue an SSL certificate for a domain |
| `wokku_set_https` | Turn the HTTP → HTTPS redirect on or off |
| `wokku_set_cdn` | Turn the Cloudflare CDN proxy on or off |
| `wokku_set_maintenance` | Turn maintenance mode on or off |

## Add-ons and databases

| Tool | What it does |
|---|---|
| `wokku_list_addons` | List an app's add-ons |
| `wokku_enable_shared_addon` | Add a free shared postgres, mariadb or redis |
| `wokku_disable_shared_addon` | Remove a shared add-on and delete its data |
| `wokku_upgrade_dedicated_addon` | Move a shared add-on to its own dedicated container |
| `wokku_remove_addon` | Remove a dedicated add-on and delete its data |
| `wokku_list_databases` | List databases |
| `wokku_get_database` | Show a database |
| `wokku_create_database` | Create a dedicated database |
| `wokku_link_database` | Link a database to an app |
| `wokku_unlink_database` | Unlink a database |
| `wokku_import_database` | Import a dump (overwrites the database) |
| `wokku_resize_database` | Resize a dedicated database |
| `wokku_retry_database` | Retry a database stuck in error |
| `wokku_delete_database` | Delete a database |
| `wokku_get_database_monitor` | Connections, cache hit rate, size and top queries |
| `wokku_list_backups` | List backups |
| `wokku_create_backup` | Back up now |
| `wokku_get_backup_download_url` | Get a short-lived download link |
| `wokku_restore_backup` | Restore a backup (overwrites the database) |

## One-click templates

| Tool | What it does |
|---|---|
| `wokku_list_templates` | List one-click templates |
| `wokku_get_template` | Show a template |
| `wokku_deploy_template` | Deploy a template |

## Account and teams

| Tool | What it does |
|---|---|
| `wokku_whoami` | Show who you are signed in as |
| `wokku_list_api_tokens` | List API tokens |
| `wokku_create_api_token` | Create an API token |
| `wokku_revoke_api_token` | Revoke an API token |
| `wokku_list_ssh_keys` | List SSH keys |
| `wokku_add_ssh_key` | Add an SSH key |
| `wokku_remove_ssh_key` | Remove an SSH key |
| `wokku_list_teams` | List teams |
| `wokku_create_team` | Create a team |
| `wokku_list_team_members` | List members |
| `wokku_add_team_member` | Invite a member |
| `wokku_update_team_member` | Change a member's role |
| `wokku_remove_team_member` | Remove a member |

## Billing

| Tool | What it does |
|---|---|
| `wokku_get_current_plan` | Show your plan and limits |
| `wokku_list_invoices` | List invoices (pay in the dashboard) |

See [Claude Code setup](/docs/mcp/setup) to install the plugin.
