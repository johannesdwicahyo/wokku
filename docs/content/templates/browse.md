# Browse Templates

Explore 100+ pre-configured app templates ready to deploy in one click.

## Browse

:::tabs
::web-ui
Go to **Templates** in the sidebar. Browse by category or search by name.

::cli
```bash
wokku templates
wokku templates --category cms
```

::api
```bash
curl https://wokku.dev/api/v1/templates \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"List all available templates"* or *"Show me CMS templates"*

::mobile
Tap **Templates** in the bottom navigation.
:::

## Popular Templates

| Template | Category | Description |
|----------|----------|-------------|
| Ghost | CMS | Modern publishing platform |
| WordPress | CMS | World's most popular CMS |
| n8n | Automation | Workflow automation tool |
| Uptime Kuma | Monitoring | Self-hosted uptime monitoring |
| Umami | Analytics | Privacy-focused web analytics |
| Grafana | Monitoring | Metrics visualization |
| Vaultwarden | Security | Bitwarden-compatible password manager |
| NocoDB | Database | Open-source Airtable alternative |
| Minio | Storage | S3-compatible object storage |
| Gitea | Development | Lightweight Git hosting |
| Plausible | Analytics | Privacy-friendly analytics |
| Listmonk | Email | Newsletter and mailing list manager |

## Categories

- **CMS** — Ghost, WordPress, Strapi, Directus
- **Automation** — n8n, Activepieces, Huginn
- **Monitoring** — Uptime Kuma, Grafana, Prometheus
- **Analytics** — Umami, Plausible, Matomo
- **Development** — Gitea, Code Server, Excalidraw
- **Communication** — Mattermost, Rocket.Chat
- **Productivity** — Vikunja, Outline, Wiki.js
- **Media** — Jellyfin, Navidrome, PhotoPrism
- **Security** — Vaultwarden, Keycloak, Authentik
- **Infrastructure** — Portainer, Traefik, Nginx Proxy Manager
