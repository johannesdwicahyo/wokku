# Claude Code (MCP) Setup

Manage your Wokku apps directly from [Claude Code](https://docs.anthropic.com/en/docs/claude-code) using natural language. 55 tools covering 100% of the Wokku API.

## Prerequisites

- A Wokku account with an API token
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Ruby 3.0+ (no gems required)

## Setup

### 1. Download the MCP server

```bash
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/mcp/server.rb -o wokku-mcp.rb
```

### 2. Get your API token

:::tabs
::web-ui
Go to **Settings → API Tokens → Create Token**. Copy the token.

::cli
```bash
wokku tokens:create --name claude-mcp
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/auth/tokens \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "claude-mcp"}'
```
:::

### 3. Add to Claude Code

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://wokku.dev/api/v1 \
  -e WOKKU_API_TOKEN=your-token-here \
  -- ruby wokku-mcp.rb
```

Or add to your project's `.claude/settings.local.json`:

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

### 4. Verify

Restart Claude Code and ask:

```
List my Wokku apps
```

## Example Prompts

- "List my servers and their status"
- "Deploy a Ghost blog on server 1"
- "Show me the logs for my-app"
- "Set DATABASE_URL on my-app to postgres://..."
- "Add the domain blog.example.com to my-app and enable SSL"
- "Scale my-app to 2 web dynos"
- "Rollback my-app to the previous release"
- "Create a backup of my production database"
- "Invite alice@example.com to the engineering team"
- "Set up a Slack notification for deploy failures"

## Self-Hosted

If you're running Wokku on your own server, change the API URL:

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://paas.mycompany.com/api/v1 \
  -e WOKKU_API_TOKEN=your-token \
  -- ruby wokku-mcp.rb
```

## Troubleshooting

**"Cannot connect"** — Check that `WOKKU_API_URL` is correct and the server is reachable.

**"Invalid or expired token"** — Generate a new API token from your dashboard.

**Tools not showing up** — Restart Claude Code. Run `claude mcp list` to verify the server is connected.

See [Available Tools](/docs/mcp/tools) for the full list of 55 tools.
