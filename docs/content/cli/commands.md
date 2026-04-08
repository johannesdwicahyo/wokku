# Commands Reference

All available CLI commands.

## Authentication

| Command | Description |
|---------|-------------|
| `wokku auth:login` | Log in to your account |
| `wokku auth:logout` | Log out |
| `wokku auth:whoami` | Show current user |
| `wokku tokens:create --name NAME` | Create API token |
| `wokku tokens:revoke ID` | Revoke API token |

## Apps

| Command | Description |
|---------|-------------|
| `wokku apps` | List all apps |
| `wokku apps:create NAME --server SERVER` | Create an app |
| `wokku apps:info APP` | Show app details |
| `wokku apps:destroy APP` | Delete an app |

## Process Management

| Command | Description |
|---------|-------------|
| `wokku ps APP` | Show process state |
| `wokku ps:scale APP web=N worker=N` | Scale processes |
| `wokku ps:restart APP` | Restart app |
| `wokku ps:stop APP` | Stop app |
| `wokku ps:start APP` | Start app |

## Config

| Command | Description |
|---------|-------------|
| `wokku config APP` | Show config vars |
| `wokku config:set APP KEY=VAL` | Set config vars |
| `wokku config:unset APP KEY` | Remove config vars |

## Domains

| Command | Description |
|---------|-------------|
| `wokku domains APP` | List domains |
| `wokku domains:add APP DOMAIN` | Add a domain |
| `wokku domains:remove APP DOMAIN` | Remove a domain |

## Releases

| Command | Description |
|---------|-------------|
| `wokku releases APP` | List releases |
| `wokku rollback APP RELEASE_ID` | Rollback to a release |

## Logs

| Command | Description |
|---------|-------------|
| `wokku logs APP` | View logs |
| `wokku logs APP --num N` | View last N lines |
| `wokku logs APP --tail` | Stream logs |

## Databases

| Command | Description |
|---------|-------------|
| `wokku addons APP` | List linked databases |
| `wokku addons:add APP TYPE` | Add a database |
| `wokku addons:remove APP ADDON` | Remove a database |
| `wokku backups DB` | List backups |
| `wokku backups:create DB` | Create a backup |

## Templates

| Command | Description |
|---------|-------------|
| `wokku templates` | List templates |
| `wokku deploy SLUG --server SERVER` | Deploy a template |

## Servers

| Command | Description |
|---------|-------------|
| `wokku servers` | List servers |
| `wokku servers:add NAME --host HOST` | Add a server |

## Activity

| Command | Description |
|---------|-------------|
| `wokku activity` | View recent activity |
