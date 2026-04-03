# Push Notification Delivery — Design Spec

## Goal

Add push notification delivery to the Wokku backend so the mobile app receives real-time alerts for deploy, backup, and app crash events via Expo Push API.

## Architecture

Push notifications are the 6th channel in the existing `Notification` model, alongside email, Slack, Discord, Telegram, and webhook. Users configure push notifications the same way they configure other channels — by creating a `Notification` record with `channel: :push` and selecting which events to receive.

When an event fires, `NotifyJob` delegates to `PushNotificationService`, which finds all `DeviceToken`s for the team's members and sends via Expo Push API using the `expo-server-sdk` gem.

## Components

### 1. Notification Model Change

Add `push: 5` to the existing channel enum:

```ruby
enum :channel, { email: 0, slack: 1, webhook: 2, discord: 3, telegram: 4, push: 5 }
```

No migration needed — just an enum value.

### 2. PushNotificationService

New service at `app/services/push_notification_service.rb`.

Responsibilities:
- Accept a notification, deploy, and event
- Find all `DeviceToken`s for users in the notification's team
- Build Expo push message (title, body, data for deep linking)
- Send via `expo-server-sdk` gem
- Store ticket IDs for receipt checking
- Handle errors gracefully (log, don't crash)

Interface:
```ruby
PushNotificationService.new(notification, deploy, event).deliver!
```

### 3. NotifyJob Addition

Add a `when "push"` case to the existing switch:

```ruby
when "push"
  PushNotificationService.new(notification, deploy, event).deliver!
```

### 4. Wire NotifyJob into Event Sources

Currently `NotifyJob` is defined but never called. Wire it into:

- `DeployJob` — on success (`deploy_succeeded`) and failure (`deploy_failed`)
- `GithubDeployJob` — on success and failure
- `BackupJob` — on completion (`backup_completed`) and failure (`backup_failed`)
- `PrPreviewDeployJob` — on success and failure

Pattern for each job:
```ruby
# After deploy succeeds
fire_notifications(app.team, "deploy_succeeded", deploy)

# Helper method in ApplicationJob or a concern
def fire_notifications(team, event, deploy)
  Notification.where(team: team).find_each do |notification|
    NotifyJob.perform_later(notification.id, event, deploy.id)
  end
end
```

### 5. PushReceiptCheckJob

Expo returns tickets immediately but receipts (delivery confirmation) are available ~15 minutes later. Invalid tokens (uninstalled apps) are reported via receipts.

- Runs every 30 minutes via Solid Queue recurring schedule
- Checks stored ticket IDs against Expo Receipts API
- Deletes `DeviceToken`s that return `DeviceNotRegistered`
- Logs errors for debugging

### 6. Push Ticket Storage

Add a `push_tickets` table to store Expo ticket IDs for receipt checking:

```
push_tickets
  id
  device_token_id (FK)
  ticket_id (string) — Expo ticket ID
  status (string) — ok, error
  checked_at (datetime, nullable)
  created_at
```

Tickets older than 24 hours are cleaned up automatically.

## Push Payload Format

```json
{
  "to": "ExponentPushToken[xxx]",
  "title": "Deploy Succeeded",
  "body": "my-app deployed successfully (abc123f) v5",
  "data": {
    "type": "deploy",
    "app_id": 1,
    "deploy_id": 42,
    "event": "deploy_succeeded"
  },
  "sound": "default",
  "categoryId": "deploy"
}
```

The `data` field enables deep linking — the mobile app reads `type` and `app_id` to navigate to the right screen.

### Event-specific titles and categories

| Event | Title | Category |
|-------|-------|----------|
| deploy_succeeded | Deploy Succeeded | deploy |
| deploy_failed | Deploy Failed | deploy |
| app_crashed | App Crashed | alert |
| backup_completed | Backup Completed | backup |
| backup_failed | Backup Failed | alert |

## Gem

`expo-server-sdk` — Ruby SDK for Expo Push API.

Add to `Gemfile`:
```ruby
gem "expo-server-sdk"
```

## Files

| Action | File |
|--------|------|
| Create | `app/services/push_notification_service.rb` |
| Create | `app/jobs/push_receipt_check_job.rb` |
| Create | `db/migrate/xxx_create_push_tickets.rb` |
| Create | `app/models/push_ticket.rb` |
| Create | `app/concerns/notifiable.rb` (shared `fire_notifications` helper) |
| Modify | `app/models/notification.rb` — add `push: 5` to enum |
| Modify | `app/jobs/notify_job.rb` — add `when "push"` case |
| Modify | `app/jobs/deploy_job.rb` — call `fire_notifications` |
| Modify | `app/jobs/github_deploy_job.rb` — call `fire_notifications` |
| Modify | `ee/app/jobs/billing_grace_check_job.rb` — call `fire_notifications` (optional) |
| Modify | `Gemfile` — add `expo-server-sdk` |
| Create | `test/services/push_notification_service_test.rb` |
| Create | `test/jobs/push_receipt_check_job_test.rb` |
| Create | `test/models/push_ticket_test.rb` |

## Testing Strategy

- Stub `Expo::Push::Client` in all tests
- Test `PushNotificationService` with mock Expo client — verify correct payload format, token lookup, error handling
- Test `PushReceiptCheckJob` — verify it deletes invalid tokens
- Test `NotifyJob` push case — verify it delegates to service
- Test `fire_notifications` in `DeployJob` — verify NotifyJob is enqueued

## Not in Scope

- Push notification preferences UI in the web dashboard (separate feature)
- iOS/Android notification categories/actions (mobile app handles this)
- Rich push (images, action buttons) — basic text notifications only for now
- Rate limiting push notifications (low volume, not needed yet)
