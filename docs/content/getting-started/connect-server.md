# Connect a Server

Connect your Dokku server to Wokku to start deploying apps.

## Prerequisites

- A VPS or dedicated server with [Dokku](https://dokku.com) installed
- SSH access to the server
- Your SSH private key

## Add a Server

:::tabs
::web-ui
1. Go to **Servers → Add Server**
2. Enter a name for your server (e.g., "production")
3. Enter the hostname or IP address
4. Set the SSH port (default: 22)
5. Paste your SSH private key
6. Click **Connect**

Wokku connects over SSH, verifies Dokku is installed, and syncs all existing apps and databases.

::cli
```bash
wokku servers:add production \
  --host dokku.example.com \
  --ssh-key ~/.ssh/id_ed25519
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/servers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "hostname": "dokku.example.com",
    "ssh_port": 22,
    "ssh_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n..."
  }'
```

::mcp
Server creation requires an SSH key, which is best done through the Web UI or CLI.

::mobile
Tap **Servers → +**, enter hostname and SSH details, then tap **Connect**.
:::

## Verify Connection

After connecting, Wokku automatically:

- Tests the SSH connection
- Detects the Dokku version
- Syncs all existing apps, databases, and domains
- Starts collecting health metrics (CPU, memory, disk)

You can check server status anytime:

:::tabs
::web-ui
Go to **Servers** and check the status indicator (green = healthy).

::cli
```bash
wokku servers
```

::api
```bash
curl https://wokku.dev/api/v1/servers/1/status \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"What's the status of my servers?"*

::mobile
Server health is shown on the Servers tab with color indicators.
:::

## Next Steps

- [Deploy your first app](/docs/getting-started/first-deploy)
- [Browse 1-click templates](/docs/templates/browse)
