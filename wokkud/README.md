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
- `WOKKUD_IMAGE_SCAN` — set to `1` to run Trivy image vulnerability scans on this host (off by default; also needs `c.image_scans = true` on the control plane). Scans run in a throwaway container (no network, read-only, all caps dropped) one at a time, never during a build, and fail as `disk_full` above 85% disk used
- `WOKKUD_SCAN_MEMORY` / `WOKKUD_SCAN_PIDS` / `WOKKUD_SCAN_CPUS` — scanner caps (defaults `2g` / `512` / `2`)

The scanner caches its vulnerability databases in the `wokku-trivy-cache` Docker volume (DB refreshed daily, Java DB weekly, about 1 GB). See the "Image scanning" docs guide.

## Develop
    go test ./... && go vet ./...

## Install on a host
    wokkud/deploy/install.sh root@<your-host> "<ingest-token>" https://<your-control-plane>
