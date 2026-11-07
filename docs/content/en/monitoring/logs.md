---
title: Logs
summary: Read, search and live-tail your app's stdout and stderr from the dashboard, CLI, API or Claude.
last_updated: 2026-11-07
---

You'll read your app's logs. Wokku collects everything your containers write to stdout and stderr — print to stdout and it shows up here.

## View logs

:::tabs
::web-ui
Open your app → **Runtime** → **Logs**.

- **Search** and the **level** dropdown query stored history.
- **Live tail** streams new lines as they arrive; **follow** auto-refreshes the view.
- **Filter visible logs** and the Errors / Warnings pills narrow what's already on screen.

::cli
```bash
wokku logs my-app              # last 100 lines
wokku logs my-app --lines 500  # last 500 lines
wokku logs my-app -f           # live tail (also --follow)
```

::api
```bash
curl -G https://wokku.cloud/api/v1/apps/my-app/logs \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "lines=200" \
  --data-urlencode "level=error" \
  --data-urlencode "q=timeout"
```

| Param | Meaning |
|---|---|
| `lines` | Number of lines, 1–1000 (default 100) |
| `since`, `until` | ISO 8601 times (default: the last 24 hours) |
| `level` | `error`, `warn`, `info` or `debug` |
| `q` | Text to search for |
| `follow=1` | Stream live lines as plain text |

::mcp
Ask Claude: *"Show me the last 200 error lines for my-app."*
:::

## Log levels

Each line gets a level from the words in it:

| Level | Matches |
|---|---|
| error | `ERROR`, `FATAL`, `CRITICAL`, `exception`, `panic`, `traceback` |
| warn | `WARN`, `WARNING` |
| info | `INFO`, `NOTICE`, and anything that matches nothing else |
| debug | `DEBUG`, `TRACE`, `VERBOSE` |

Matching ignores case, so a JSON line like `{"level":"error",...}` counts as an error.

## Limits

- Lines over 16 KB are cut to 16 KB.
- Build output isn't here — read it on the deploy in the **Deploy** tab.
- Logs are kept for a limited window. Ship anything you must keep long-term from your app to your own log service.
- There are no log drains. To forward logs, send them from your app.

## See also

- [Metrics](/docs/monitoring/metrics) — CPU, memory, requests and Web Vitals
- [Audit log](/docs/monitoring/audit-log) — who changed what in your workspace
