---
title: CLI Commands
summary: Every wokku command you will use, grouped by task, with its arguments.
eyebrow: cli
last_updated: 2026-11-07
---

Find the command for a task. `APP` is your app's name (for example `my-app`) and `DB` is a database name. Run `wokku help` for the same list in your terminal.

Add `--json` to any read command for machine-readable output, or `--quiet` (`-q`) to hide status messages.

## Account

| Command | What it does |
|---|---|
| `wokku auth:login` | Sign in through your browser |
| `wokku auth:logout` | Sign out and revoke this session's token |
| `wokku auth:whoami` | Show who you are signed in as |
| `wokku tokens` | List your API tokens |
| `wokku tokens:create NAME` | Create an API token (shown once) |
| `wokku tokens:revoke TOKEN_ID` | Revoke an API token |
| `wokku ssh-keys` | List your SSH keys |
| `wokku ssh-keys:add [PATH] --name LABEL` | Upload a public key (defaults to `~/.ssh/id_ed25519.pub`) |
| `wokku ssh-keys:remove NAME` | Remove a key (or `--fingerprint SHA`) |
| `wokku doctor` | Check your sign-in, CLI version and app health in one go |
| `wokku version` | Show the CLI version |

## Apps

| Command | What it does |
|---|---|
| `wokku apps` | List your apps |
| `wokku apps:info APP` | Show app details |
| `wokku apps:create NAME` | Create an app. Flags: `--branch BRANCH`, `--box-size SIZE`, `--shared postgres,redis`, `--dedicated-db postgres\|mysql\|mongodb`, `--dedicated-redis` |
| `wokku apps:update APP --branch BRANCH` | Change the deploy branch |
| `wokku apps:rename APP NEW_NAME` | Rename an app (its `wokku.app` address changes) |
| `wokku apps:clone APP NEW_NAME` | Copy an app's settings (not env vars or data) |
| `wokku apps:lock APP` / `apps:unlock APP` | Block or allow new deploys |
| `wokku apps:transfer APP EMAIL` | Offer an app to another user |
| `wokku transfers` | List transfers waiting on you or someone else |
| `wokku transfers:accept ID` / `:decline ID` / `:cancel ID` | Answer or cancel a transfer |
| `wokku apps:destroy APP` | Delete an app (asks to confirm) |

## Deploys and releases

| Command | What it does |
|---|---|
| `wokku deploys APP` | List deploys |
| `wokku deploys:info APP DEPLOY_ID` | Show a deploy and its build log |
| `wokku deploy:tarball APP [DIR]` | Deploy a local folder without `git push` |
| `wokku redeploy APP` | Rebuild and deploy the latest source |
| `wokku releases APP` | List releases |
| `wokku releases:info APP RELEASE_ID` | Show one release |
| `wokku rollback APP RELEASE_ID` | Roll back to a release |
| `wokku ai:diagnose APP [DEPLOY_ID]` | Ask AI why a deploy failed |

## GitHub and previews

| Command | What it does |
|---|---|
| `wokku github:repos [OWNER/REPO]` | List repos the Wokku GitHub App can see, or a repo's branches |
| `wokku github:connect APP OWNER/REPO [--branch BRANCH]` | Deploy on every push to a repo |
| `wokku github:disconnect APP` | Stop deploying from GitHub |
| `wokku previews APP` | List pull-request preview apps |
| `wokku previews:settings APP --on\|--off [--database empty\|snapshot\|shared]` | Turn previews on or off and pick their database |
| `wokku previews:destroy APP PR_NUMBER` | Remove a preview app |

## Config

| Command | What it does |
|---|---|
| `wokku config APP` | Show environment variables |
| `wokku config:get APP KEY` | Show one variable |
| `wokku config:set APP KEY=VALUE ...` | Set variables (restart the app to apply) |
| `wokku config:unset APP KEY ...` | Remove variables |
| `wokku config:export APP` | Print variables as a `.env` file |

## Running and scaling

| Command | What it does |
|---|---|
| `wokku ps APP` | Show running processes |
| `wokku ps:restart APP` / `ps:stop APP` / `ps:start APP` | Restart, stop or start the app |
| `wokku ps:scale APP web=2 worker=1` | Change how many of each process run |
| `wokku ps:dynos APP` | Show each process type's size and cost |
| `wokku ps:sizes` | List available sizes |
| `wokku ps:resize APP TYPE --memory MB [--cpu N]` | Change a process type's CPU and RAM |
| `wokku run APP -- COMMAND` | Run a one-off command, e.g. `wokku run my-app -- bin/rails db:migrate` |
| `wokku run:status APP RUN_ID` | Check a one-off run |
| `wokku ps:exec APP -- COMMAND` | Run an interactive command in a one-off container |
| `wokku enter APP` | Open a shell in the running container |
| `wokku cron APP` | List scheduled tasks |
| `wokku cron:add APP --schedule '0 3 * * *' --command 'CMD' [--description 'TEXT']` | Add a scheduled task |
| `wokku cron:remove APP TASK_ID` | Remove a scheduled task |

## Logs and monitoring

| Command | What it does |
|---|---|
| `wokku logs APP [--lines N] [-f]` | Show logs; `-f` (`--follow`) streams them |
| `wokku metrics APP` | Latest CPU and memory |
| `wokku monitor APP` | Request totals and slowest URLs |
| `wokku vitals APP` | Core Web Vitals (p75) |
| `wokku vitals:rotate-token APP` | Issue a new web-vitals token |
| `wokku incidents [--all] [--app APP]` | List outages (open ones by default) |
| `wokku incidents:info ID` | Show one incident |
| `wokku alerts:mutes` | List your phone alert mutes |
| `wokku alerts:mute [--app APP] [--event EVENT] [--for 1h\|8h\|1d]` | Mute phone alerts |
| `wokku alerts:unmute ID` | Remove a mute |
| `wokku notifications` | List notification channels |
| `wokku notifications:add --team TEAM_ID --channel email --events EVENT1,EVENT2` | Add an email notification |
| `wokku notifications:test ID` | Send a test message |
| `wokku notifications:remove ID` | Remove a channel |
| `wokku activity` | Recent activity |

## Domains and HTTPS

| Command | What it does |
|---|---|
| `wokku domains APP` | List domains |
| `wokku domains:add APP DOMAIN` | Add a custom domain |
| `wokku domains:remove APP DOMAIN` | Remove a domain |
| `wokku domains:clear APP` | Remove every custom domain |
| `wokku certs:enable APP DOMAIN` | Issue a Let's Encrypt certificate |
| `wokku https APP` / `https:on APP` / `https:off APP` | Show or set the HTTP → HTTPS redirect |
| `wokku cdn APP` / `cdn:on APP` / `cdn:off APP` | Show or set the Cloudflare CDN proxy |
| `wokku maintenance APP` / `maintenance:on APP` / `maintenance:off APP` | Show or set maintenance mode |

## Add-ons and databases

| Command | What it does |
|---|---|
| `wokku addons APP` | List an app's add-ons |
| `wokku addons:shared:enable APP ENGINE` | Add a free shared `postgres`, `mariadb` or `redis` |
| `wokku addons:shared:disable APP ENGINE` | Remove a shared add-on and delete its data |
| `wokku addons:dedicated:upgrade APP ENGINE` | Move a shared add-on to its own dedicated container |
| `wokku addons:remove APP ADDON_ID` | Remove a dedicated add-on and delete its data |
| `wokku databases` | List your databases |
| `wokku databases:info DB` | Show database details |
| `wokku databases:create NAME --type postgres` | Create a dedicated database |
| `wokku databases:link DB APP [--alias ALIAS]` | Link a database to an app (sets its URL variable) |
| `wokku databases:unlink DB APP` | Unlink a database |
| `wokku databases:connect DB` | Open an interactive database client |
| `wokku databases:import DB FILE` | Import a dump (overwrites the database) |
| `wokku databases:resize DB --cpu 0.5 --memory 1024 --disk 10` | Resize a dedicated database (disk only grows) |
| `wokku databases:retry DB` | Retry a database stuck in error |
| `wokku databases:destroy DB` | Delete a database |
| `wokku db:monitor DB` | Connections, cache hit rate, size and slow queries |
| `wokku backups DB` | List backups |
| `wokku backups:capture DB` | Back up now |
| `wokku backups:download DB BACKUP_ID [FILE]` | Download a backup |
| `wokku backups:restore DB BACKUP_ID` | Restore a backup (overwrites the database) |

## One-click templates

| Command | What it does |
|---|---|
| `wokku templates` | List templates |
| `wokku templates:info SLUG` | Show a template |
| `wokku deploy SLUG [--name NAME]` | Deploy a template |

## Teams

| Command | What it does |
|---|---|
| `wokku teams` | List your teams |
| `wokku teams:create NAME` | Create a team |
| `wokku teams:members TEAM_ID` | List members |
| `wokku teams:members:add TEAM_ID --email EMAIL [--role member\|admin]` | Add a member |
| `wokku teams:members:role TEAM_ID MEMBERSHIP_ID viewer\|member\|admin` | Change a member's role |
| `wokku teams:members:remove TEAM_ID MEMBERSHIP_ID` | Remove a member |

## Billing

| Command | What it does |
|---|---|
| `wokku billing:plan` | Show your plan and limits |
| `wokku billing:invoices` | List invoices (pay in the dashboard) |

## Local development

| Command | What it does |
|---|---|
| `wokku dev APP -- COMMAND` | Run a local command with the app's production env and a read-only database tunnel. Flags: `--duration MIN`, `--rw`, `--local-port N` |
| `wokku tunnel PORT [--subdomain NAME]` | Share a local port on a public HTTPS URL |
