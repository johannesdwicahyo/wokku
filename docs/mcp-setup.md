# Wokku MCP Server — AI-Powered Deployment

Manage your Wokku apps directly from Claude Code, Cursor, or any MCP-compatible AI assistant.

## Setup

### 1. Get your API token

```bash
curl -X POST https://wokku.dev/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "your@email.com", "password": "your_password"}'
```

Save the returned token.

### 2. Add to Claude Code

Add to your `~/.claude.json`:

```json
{
  "mcpServers": {
    "wokku": {
      "command": "ruby",
      "args": ["/path/to/wokku/mcp/server.rb"],
      "env": {
        "WOKKU_API_TOKEN": "your_api_token",
        "WOKKU_API_URL": "https://wokku.dev/api/v1"
      }
    }
  }
}
```

### 3. Available Commands

Once configured, you can tell Claude Code:

- "List my Wokku apps"
- "Deploy Ghost CMS on my server"
- "Show logs for my-app"
- "Set DATABASE_URL for my-app"
- "Restart my-app"
- "Delete my-app"
- "Scale my-app to 2 web dynos"
- "Show domains for my-app"
- "Enable SSL for my domain"
- "Add a Postgres database to my-app"
- "List add-ons for my-app"
- "Show recent activity"
- "Create a new app called blog on server 1"

### 4. API Reference

| Tool | Description |
|------|-------------|
| `wokku_list_apps` | List all applications |
| `wokku_get_app` | Get app details |
| `wokku_create_app` | Create a new app |
| `wokku_restart_app` | Restart an app |
| `wokku_stop_app` | Stop an app |
| `wokku_get_logs` | View app logs |
| `wokku_get_config` | Get environment variables |
| `wokku_set_config` | Set environment variables |
| `wokku_deploy_template` | Deploy from template |
| `wokku_list_domains` | List app domains |
| `wokku_scale_app` | Scale app processes |
| `wokku_delete_app` | Delete an application |
| `wokku_enable_ssl` | Enable SSL for an app domain |
| `wokku_list_addons` | List add-ons for an app |
| `wokku_add_addon` | Add a database add-on to an app |
| `wokku_remove_addon` | Remove an add-on from an app |
| `wokku_list_activities` | List recent activity log |
