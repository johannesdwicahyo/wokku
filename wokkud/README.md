# wokkud

Wokku host agent. One static Go binary per host. Dials OUT to the
control plane only — no inbound ports.

Duties: 15s heartbeat with vitals (disk/mem/load/docker), container die
events with exit code/OOM flag/recent logs, typed lifecycle ops
(stack converge/remove/run), service ops (datastore create/destroy/
export/import), build execution, cron runs, and router config rendering
for Caddy.

## Config (env, `/etc/wokkud/env` in prod)
- `WOKKUD_URL`   — your control plane's base URL; must be `https://`, except plain `http://` to localhost (set `WOKKUD_ALLOW_INSECURE_URL=1` to override, which sends the token in cleartext)
- `WOKKUD_TOKEN` — the host's ingest token (shown when you connect a
  server in the dashboard)
- `WOKKUD_INTERVAL` — heartbeat cadence (default 15s)

## Develop
    go test ./... && go vet ./...

## Install on a host
    wokkud/deploy/install.sh root@<your-host> "<ingest-token>" https://<your-control-plane>
