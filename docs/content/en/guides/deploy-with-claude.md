# Deploy with Claude (MCP)

Wokku ships a Model Context Protocol (MCP) server, so an AI agent like Claude
can provision and operate your apps in plain language — create an app, add a
database, deploy, check logs and vitals — without you leaving your editor.

## 1. Set up the MCP server

Install it into Claude Code with your Wokku CLI token:

```bash
wokku mcp:install
```

This registers the Wokku MCP server with Claude Code using your active token.
Full details in [MCP Setup](/docs/mcp/setup); the available tools are listed in
[MCP Tools](/docs/mcp/tools).

## 2. Ask Claude to deploy

Once connected, just describe what you want:

> *"Create an app called `my-api` on my server, add a Postgres database, set
> `RAILS_ENV=production`, and deploy it."*

Claude calls the Wokku tools in order — `create_app`, `create_database`,
`set_config`, `deploy_app` — and reports back each result.

## What Claude can do

| Task | Example prompt |
|---|---|
| Create & deploy | *"Deploy a Ghost blog called my-blog on server 1"* |
| Databases | *"Add a Redis instance to my-api and link it"* |
| Config | *"Set `LOG_LEVEL=debug` on my-api"* |
| Observe | *"Show me the last 100 log lines for my-api"* · *"What are my-api's vitals?"* |
| Scale | *"Scale my-api to 2 web and 1 worker"* |
| Operate | *"Roll back my-api to the previous release"* |
| Domains | *"Add the domain api.example.com to my-api with SSL"* |

The MCP surface mirrors the [CLI](/docs/cli/commands) and
[API](/docs/api/endpoints) — anything you can script, Claude can drive.

## Switch or sign out

```bash
wokku mcp:switch     # re-point at the active token / endpoint
wokku mcp:logout     # remove the MCP server
```

## Troubleshooting

- **"install Claude Code first"** — the `claude` CLI must be on your PATH; install Claude Code, then re-run `wokku mcp:install`.
- **Auth errors** — your CLI token may have expired; re-authenticate with the CLI and run `wokku mcp:switch`.
- **Tool not found** — update the plugin: re-run `wokku mcp:install` to refresh the registered server.

## Next steps

- [MCP Setup](/docs/mcp/setup) · [MCP Tools](/docs/mcp/tools) · [CLI](/docs/cli/commands)
