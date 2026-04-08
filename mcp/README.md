# Wokku MCP Server

Manage your [Wokku](https://wokku.dev) apps, databases, and deployments directly from [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

> **Requirements:** Ruby 3.0+ (no gems needed — uses only Ruby stdlib)

## Quick Setup

### 1. Download the server

```bash
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/mcp/server.rb -o wokku-mcp.rb
```

### 2. Generate an API token

Go to your Wokku dashboard > **Settings > API Tokens > Create Token**.

Or via CLI:

```bash
wokku tokens:create --name claude-mcp
```

Or via API:

```bash
curl -X POST https://wokku.dev/api/v1/auth/tokens \
  -H "Authorization: Bearer <your-login-token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "claude-mcp"}'
```

### 3. Add to Claude Code

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://wokku.dev/api/v1 \
  -e WOKKU_API_TOKEN=your-token-here \
  -- ruby wokku-mcp.rb
```

Or add manually to your project's `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "wokku": {
      "command": "ruby",
      "args": ["wokku-mcp.rb"],
      "env": {
        "WOKKU_API_URL": "https://wokku.dev/api/v1",
        "WOKKU_API_TOKEN": "your-token-here"
      }
    }
  }
}
```

**Self-hosted?** Change `WOKKU_API_URL` to your instance (e.g., `https://paas.mycompany.com/api/v1`).

### 4. Verify

Start a new Claude Code session and ask:

```
List my Wokku apps
```

## Available Tools (55 tools)

### Servers
| Tool | Description |
|------|-------------|
| `wokku_list_servers` | List all connected Dokku servers |
| `wokku_get_server` | Get server details |
| `wokku_server_status` | Get server health (CPU, memory, disk) |

### Apps
| Tool | Description |
|------|-------------|
| `wokku_list_apps` | List all applications |
| `wokku_get_app` | Get app details |
| `wokku_create_app` | Create a new application |
| `wokku_update_app` | Update app (rename, change deploy branch) |
| `wokku_delete_app` | Delete an application |
| `wokku_restart_app` | Restart an application |
| `wokku_stop_app` | Stop an application |
| `wokku_start_app` | Start a stopped application |

### Config (Environment Variables)
| Tool | Description |
|------|-------------|
| `wokku_get_config` | Get environment variables |
| `wokku_set_config` | Set environment variables |
| `wokku_unset_config` | Remove environment variables |

### Domains & SSL
| Tool | Description |
|------|-------------|
| `wokku_list_domains` | List domains for an app |
| `wokku_add_domain` | Add a custom domain |
| `wokku_remove_domain` | Remove a domain |
| `wokku_enable_ssl` | Enable Let's Encrypt SSL |

### Releases & Rollbacks
| Tool | Description |
|------|-------------|
| `wokku_list_releases` | List all releases |
| `wokku_get_release` | Get release details |
| `wokku_rollback` | Rollback to a previous release |

### Process Scaling
| Tool | Description |
|------|-------------|
| `wokku_get_ps` | Get current process/dyno info |
| `wokku_scale_app` | Scale web/worker dynos |

### Health Checks
| Tool | Description |
|------|-------------|
| `wokku_get_checks` | Get health check config |
| `wokku_update_checks` | Update health check config |

### Logs & Deploys
| Tool | Description |
|------|-------------|
| `wokku_get_logs` | Get application logs |
| `wokku_list_deploys` | List deploy history |
| `wokku_get_deploy` | Get deploy details (status, duration, commit) |

### Addons (App-scoped Databases)
| Tool | Description |
|------|-------------|
| `wokku_list_addons` | List linked databases for an app |
| `wokku_add_addon` | Add a database to an app |
| `wokku_remove_addon` | Remove a database from an app |

### Log Drains
| Tool | Description |
|------|-------------|
| `wokku_list_log_drains` | List log drains |
| `wokku_add_log_drain` | Forward logs to external service |
| `wokku_remove_log_drain` | Remove a log drain |

### Templates
| Tool | Description |
|------|-------------|
| `wokku_list_templates` | List all 1-click templates |
| `wokku_get_template` | Get template details |
| `wokku_deploy_template` | Deploy a template (ghost, wordpress, n8n, etc.) |

### Databases (Standalone)
| Tool | Description |
|------|-------------|
| `wokku_list_databases` | List all databases |
| `wokku_get_database` | Get database details |
| `wokku_create_database` | Create a standalone database |
| `wokku_delete_database` | Delete a database |
| `wokku_link_database` | Link database to an app |
| `wokku_unlink_database` | Unlink database from an app |

### Database Backups
| Tool | Description |
|------|-------------|
| `wokku_list_backups` | List backups for a database |
| `wokku_create_backup` | Create an on-demand backup |

### SSH Keys
| Tool | Description |
|------|-------------|
| `wokku_list_ssh_keys` | List SSH keys |
| `wokku_add_ssh_key` | Add an SSH public key |
| `wokku_remove_ssh_key` | Remove an SSH key |

### Teams
| Tool | Description |
|------|-------------|
| `wokku_list_teams` | List teams |
| `wokku_create_team` | Create a new team |
| `wokku_list_team_members` | List team members |
| `wokku_add_team_member` | Invite a member |
| `wokku_remove_team_member` | Remove a member |

### Notifications
| Tool | Description |
|------|-------------|
| `wokku_list_notifications` | List notification channels |
| `wokku_create_notification` | Create notification (Slack, Discord, email, webhook, Telegram) |
| `wokku_delete_notification` | Delete a notification channel |

### Activities
| Tool | Description |
|------|-------------|
| `wokku_list_activities` | View recent activity log |

## Example Prompts

Once connected, you can ask Claude things like:

- "List my servers and their status"
- "Deploy a Ghost blog on server 1"
- "Show me the logs for my-app"
- "Set DATABASE_URL on my-app to postgres://..."
- "Remove the LEGACY_KEY env var from my-app"
- "Scale my-app to 2 web dynos"
- "Add a Redis database to my-app"
- "Add the domain blog.example.com to my-app and enable SSL"
- "Show me the deploy history for my-app"
- "Rollback my-app to the previous release"
- "Create a backup of my production database"
- "Invite alice@example.com to the engineering team as admin"
- "Set up a Slack notification for deploy failures"
- "What happened recently? Show me the activity log"

## Troubleshooting

**"Cannot connect" error** — Check that `WOKKU_API_URL` is correct and the server is reachable.

**"Invalid or expired token"** — Generate a new API token from your dashboard.

**Tools not showing up** — Restart Claude Code after adding the MCP config. Run `claude mcp list` to verify.

**Self-hosted instance** — Make sure to set `WOKKU_API_URL` to your instance URL with the `/api/v1` suffix.
