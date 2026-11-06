---
title: Every Surface
summary: "What you can do from the dashboard, the REST API, the CLI, Claude Code and the iOS app. Every dashboard action has an API endpoint, and the CLI and Claude Code cover nearly all of them."
eyebrow: api
---

# Every Surface

Wokku is API-first: every action in the dashboard goes through the same [REST API](/docs/api/endpoints) you can call yourself. The [CLI](/docs/cli/commands) and [Claude Code](/docs/mcp/tools) are built on that API, so they can do almost everything the dashboard can. The [iOS app](/docs/mobile/download) is for being on call: checking status, reading logs, restarting, rolling back and handling incidents.

✅ available · — not available

## Apps

| What you can do | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| List apps and see status | ✅ | ✅ | ✅ | ✅ | ✅ |
| Create, rename, clone, transfer, lock or delete an app | ✅ | ✅ | ✅ | ✅ | — |
| Environment variables | ✅ | ✅ | ✅ | ✅ | — |
| Domains and SSL | ✅ | ✅ | ✅ | ✅ | — |
| HTTPS, CDN and maintenance mode | ✅ | ✅ | ✅ | ✅ | — |
| GitHub auto-deploy and preview apps | ✅ | ✅ | ✅ | ✅ | — |
| Health checks | ✅ | ✅ | ✅ | ✅ | — |
| Scheduled tasks | ✅ | ✅ | ✅ | ✅ | — |
| One-off commands and terminal | ✅ | ✅ | ✅ | ✅ | — |

## Running apps

| What you can do | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Start, stop and restart | ✅ | ✅ | ✅ | ✅ | ✅ |
| Scale processes | ✅ | ✅ | ✅ | ✅ | ✅ |
| Resize (CPU, RAM, disk) | ✅ | ✅ | ✅ | ✅ | — |
| Logs | ✅ | ✅ | ✅ | ✅ | ✅ |
| Deploy history and releases | ✅ | ✅ | ✅ | ✅ | ✅ |
| Roll back a release | ✅ | ✅ | ✅ | ✅ | ✅ |
| Deploy or redeploy | ✅ | ✅ | ✅ | ✅ | — |
| Metrics and activity feed | ✅ | ✅ | ✅ | ✅ | — |
| Incidents | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mute alerts | ✅ | ✅ | ✅ | ✅ | ✅ |
| AI diagnose | ✅ | ✅ | ✅ | ✅ | — |
| Doctor (self-check) | — | ✅ | ✅ | ✅ | — |

## Databases

| What you can do | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Create, link, unlink and delete databases | ✅ | ✅ | ✅ | ✅ | — |
| Free shared add-ons and dedicated upgrades | ✅ | ✅ | ✅ | ✅ | — |
| Monitor a database | ✅ | ✅ | ✅ | ✅ | — |
| Import a dump | ✅ | ✅ | ✅ | ✅ | — |
| Backups: create, download, restore | ✅ | ✅ | ✅ | ✅ | — |

## Account and team

| What you can do | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| API tokens and SSH keys | ✅ | ✅ | ✅ | ✅ | — |
| Teams and members | ✅ | ✅ | ✅ | ✅ | — |
| Notification channels | ✅ | ✅ | ✅ | ✅ | — |
| Push alerts on your phone | — | ✅ | — | — | ✅ |
| One-click templates | ✅ | ✅ | ✅ | ✅ | — |
| Current plan | ✅ | ✅ | ✅ | ✅ | — |
| Top up balance | ✅ | ✅ | — | — | — |

## Local development

| What you can do | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Tunnels (share a local port) | ✅ | ✅ | ✅ | — | — |
| Dev sessions (local code, production env) | — | ✅ | ✅ | — | — |

Tunnels and dev sessions need a process running on your machine, so they live in the CLI rather than Claude Code. Paying always finishes in the browser.
