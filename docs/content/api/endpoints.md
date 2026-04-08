# Endpoints Reference

Base URL: `https://wokku.dev/api/v1`

All endpoints require `Authorization: Bearer TOKEN` header.

## Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/login` | Login, get session token |
| DELETE | `/auth/logout` | Logout |
| GET | `/auth/whoami` | Current user info |
| GET | `/auth/tokens` | List API tokens |
| POST | `/auth/tokens` | Create API token |
| DELETE | `/auth/tokens/:id` | Revoke token |

## Servers

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/servers` | List servers |
| GET | `/servers/:id` | Server details |
| POST | `/servers` | Add a server |
| DELETE | `/servers/:id` | Remove a server |
| GET | `/servers/:id/status` | Server health |

## Apps

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps` | List apps |
| GET | `/apps/:id` | App details |
| POST | `/apps` | Create app |
| PUT | `/apps/:id` | Update app |
| DELETE | `/apps/:id` | Delete app |
| POST | `/apps/:id/restart` | Restart |
| POST | `/apps/:id/stop` | Stop |
| POST | `/apps/:id/start` | Start |

## Config

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/config` | Get env vars |
| PUT | `/apps/:id/config` | Set env vars |
| DELETE | `/apps/:id/config` | Remove env vars |

## Domains

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/domains` | List domains |
| POST | `/apps/:id/domains` | Add domain |
| DELETE | `/apps/:id/domains/:did` | Remove domain |
| POST | `/apps/:id/domains/:did/ssl` | Enable SSL |

## Releases

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/releases` | List releases |
| GET | `/apps/:id/releases/:rid` | Release details |
| POST | `/apps/:id/releases/:rid/rollback` | Rollback |

## Processes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/ps` | Process state |
| PUT | `/apps/:id/ps` | Scale processes |

## Health Checks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/checks` | Get checks config |
| PUT | `/apps/:id/checks` | Update checks |

## Logs & Deploys

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/logs` | Get logs |
| GET | `/apps/:id/deploys` | List deploys |
| GET | `/apps/:id/deploys/:did` | Deploy details |

## Addons

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/addons` | List addons |
| POST | `/apps/:id/addons` | Add addon |
| DELETE | `/apps/:id/addons/:aid` | Remove addon |

## Log Drains

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/apps/:id/log_drains` | List drains |
| POST | `/apps/:id/log_drains` | Add drain |
| DELETE | `/apps/:id/log_drains/:did` | Remove drain |

## Templates

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/templates` | List templates |
| GET | `/templates/:id` | Template details |
| POST | `/templates/deploy` | Deploy template |

## Databases

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/databases` | List databases |
| GET | `/databases/:id` | Database details |
| POST | `/databases` | Create database |
| DELETE | `/databases/:id` | Delete database |
| POST | `/databases/:id/link` | Link to app |
| POST | `/databases/:id/unlink` | Unlink from app |

## Backups

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/databases/:id/backups` | List backups |
| POST | `/databases/:id/backups` | Create backup |

## SSH Keys

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/ssh_keys` | List keys |
| POST | `/ssh_keys` | Add key |
| DELETE | `/ssh_keys/:id` | Remove key |

## Teams

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/teams` | List teams |
| POST | `/teams` | Create team |
| GET | `/teams/:id/members` | List members |
| POST | `/teams/:id/members` | Add member |
| DELETE | `/teams/:id/members/:mid` | Remove member |

## Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/notifications` | List channels |
| POST | `/notifications` | Create channel |
| DELETE | `/notifications/:id` | Delete channel |

## Activities

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/activities` | Activity log |
