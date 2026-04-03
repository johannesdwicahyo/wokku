# Push Notification Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add push notification delivery via Expo Push API so the mobile app receives real-time alerts for deploy, backup, and crash events.

**Architecture:** Add `push` as a 6th channel to Notification model. PushNotificationService wraps the `expo-server-sdk` gem to send to device tokens. A Notifiable concern provides `fire_notifications` to all jobs. PushReceiptCheckJob cleans up invalid tokens.

**Tech Stack:** Rails 8.1, expo-server-sdk gem, Solid Queue, Minitest

---

## File Map

| File | Task | Action |
|------|------|--------|
| `Gemfile` | 1 | Modify — add `expo-server-sdk` |
| `app/models/notification.rb` | 1 | Modify — add `push: 5` to enum |
| `app/models/push_ticket.rb` | 2 | Create — model for tracking Expo tickets |
| `db/migrate/xxx_create_push_tickets.rb` | 2 | Create — migration |
| `app/services/push_notification_service.rb` | 3 | Create — Expo push delivery |
| `test/services/push_notification_service_test.rb` | 3 | Create — tests |
| `app/jobs/notify_job.rb` | 4 | Modify — add `when "push"` |
| `test/jobs/notify_job_test.rb` | 4 | Modify — add push test |
| `app/concerns/notifiable.rb` | 5 | Create — `fire_notifications` helper |
| `app/jobs/deploy_job.rb` | 5 | Modify — call `fire_notifications` |
| `app/jobs/github_deploy_job.rb` | 5 | Modify — call `fire_notifications` |
| `test/concerns/notifiable_test.rb` | 5 | Create — tests |
| `app/jobs/push_receipt_check_job.rb` | 6 | Create — receipt checker |
| `test/jobs/push_receipt_check_job_test.rb` | 6 | Create — tests |

---

### Task 1: Add expo-server-sdk gem and push channel enum

**Files:**
- Modify: `Gemfile`
- Modify: `app/models/notification.rb`

- [ ] **Step 1: Add gem to Gemfile**

Add after `gem "rack-attack"` line:

```ruby
gem "expo-server-sdk"
```

- [ ] **Step 2: Install**

Run: `bundle install`

- [ ] **Step 3: Add push to Notification enum**

Replace line 5 in `app/models/notification.rb`:

```ruby
  enum :channel, { email: 0, slack: 1, webhook: 2, discord: 3, telegram: 4, push: 5 }
```

- [ ] **Step 4: Verify**

Run: `bin/rails runner "puts Notification.channels.keys"`
Expected output should include `push`

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock app/models/notification.rb
git commit -m "feat: add expo-server-sdk gem and push channel to Notification"
```

---

### Task 2: PushTicket model and migration

**Files:**
- Create: `db/migrate/XXXXXX_create_push_tickets.rb`
- Create: `app/models/push_ticket.rb`
- Create: `test/models/push_ticket_test.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate model PushTicket device_token:references ticket_id:string status:string checked_at:datetime`

- [ ] **Step 2: Edit migration for indexes**

Edit the generated migration to add index on ticket_id:

```ruby
class CreatePushTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :push_tickets do |t|
      t.references :device_token, null: false, foreign_key: true
      t.string :ticket_id, null: false
      t.string :status, default: "pending"
      t.datetime :checked_at

      t.timestamps
    end
    add_index :push_tickets, :ticket_id, unique: true
    add_index :push_tickets, :checked_at
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 4: Write PushTicket model**

Replace `app/models/push_ticket.rb`:

```ruby
class PushTicket < ApplicationRecord
  belongs_to :device_token

  validates :ticket_id, presence: true, uniqueness: true

  scope :pending, -> { where(checked_at: nil) }
  scope :stale, -> { where(created_at: ...24.hours.ago) }
end
```

- [ ] **Step 5: Add association to DeviceToken**

Add to `app/models/device_token.rb` after `belongs_to :user`:

```ruby
  has_many :push_tickets, dependent: :destroy
```

- [ ] **Step 6: Write test**

Create `test/models/push_ticket_test.rb`:

```ruby
require "test_helper"

class PushTicketTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @device_token = DeviceToken.create!(user: @user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  test "validates ticket_id presence" do
    ticket = PushTicket.new(device_token: @device_token, ticket_id: nil)
    assert_not ticket.valid?
  end

  test "validates ticket_id uniqueness" do
    PushTicket.create!(device_token: @device_token, ticket_id: "ticket-abc")
    duplicate = PushTicket.new(device_token: @device_token, ticket_id: "ticket-abc")
    assert_not duplicate.valid?
  end

  test "pending scope returns unchecked tickets" do
    checked = PushTicket.create!(device_token: @device_token, ticket_id: "t1", checked_at: Time.current)
    pending = PushTicket.create!(device_token: @device_token, ticket_id: "t2", checked_at: nil)
    assert_includes PushTicket.pending, pending
    assert_not_includes PushTicket.pending, checked
  end

  test "belongs to device_token" do
    ticket = PushTicket.create!(device_token: @device_token, ticket_id: "t3")
    assert_equal @device_token, ticket.device_token
  end
end
```

- [ ] **Step 7: Run test**

Run: `bin/rails test test/models/push_ticket_test.rb`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add app/models/push_ticket.rb app/models/device_token.rb db/migrate/*create_push_tickets* db/schema.rb test/models/push_ticket_test.rb
git commit -m "feat: PushTicket model for tracking Expo delivery receipts"
```

---

### Task 3: PushNotificationService

**Files:**
- Create: `app/services/push_notification_service.rb`
- Create: `test/services/push_notification_service_test.rb`

- [ ] **Step 1: Write the test**

Create `test/services/push_notification_service_test.rb`:

```ruby
require "test_helper"

class PushNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @team = teams(:two)
    @app = app_records(:two)
    @deploy = @app.deploys.create!(status: :succeeded, commit_sha: "abc1234")
    @release = @app.releases.create!(version: 1, deploy: @deploy, description: "Test deploy")
    @notification = Notification.create!(team: @team, channel: :push, events: ["deploy_succeeded", "deploy_failed"])
    @device = DeviceToken.create!(user: @user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  test "delivers push to all team device tokens" do
    sent_messages = []
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |messages|
      sent_messages.concat(messages)
      messages.map { |_| Expo::Push::Ticket.new("id" => "ticket-#{SecureRandom.hex(4)}", "status" => "ok") }
    end

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)
    service.deliver!

    assert_equal 1, sent_messages.size
    msg = sent_messages.first
    assert_equal @device.token, msg[:to]
    assert_includes msg[:body], @app.name
    assert_equal "deploy", msg[:data][:type]
  end

  test "skips when no device tokens exist for team" do
    @device.destroy!

    mock_client = Object.new
    mock_client.define_singleton_method(:publish) { |msgs| raise "should not be called" }

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)
    service.deliver! # should not raise
  end

  test "creates push tickets for tracking" do
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |messages|
      messages.map { |_| Expo::Push::Ticket.new("id" => "ticket-xyz", "status" => "ok") }
    end

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)

    assert_difference "PushTicket.count", 1 do
      service.deliver!
    end
  end

  test "sets correct title for deploy_succeeded" do
    sent = []
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |msgs|
      sent.concat(msgs)
      msgs.map { |_| Expo::Push::Ticket.new("id" => "t1", "status" => "ok") }
    end

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)
    service.deliver!

    assert_equal "Deploy Succeeded", sent.first[:title]
  end

  test "sets correct title for deploy_failed" do
    sent = []
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |msgs|
      sent.concat(msgs)
      msgs.map { |_| Expo::Push::Ticket.new("id" => "t2", "status" => "ok") }
    end

    service = PushNotificationService.new(@notification, @deploy, "deploy_failed")
    service.instance_variable_set(:@client, mock_client)
    service.deliver!

    assert_equal "Deploy Failed", sent.first[:title]
  end

  test "includes deep link data" do
    sent = []
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |msgs|
      sent.concat(msgs)
      msgs.map { |_| Expo::Push::Ticket.new("id" => "t3", "status" => "ok") }
    end

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)
    service.deliver!

    data = sent.first[:data]
    assert_equal "deploy", data[:type]
    assert_equal @app.id, data[:app_id]
    assert_equal @deploy.id, data[:deploy_id]
    assert_equal "deploy_succeeded", data[:event]
  end

  test "handles expo client errors gracefully" do
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) { |_| raise StandardError, "Expo API down" }

    service = PushNotificationService.new(@notification, @deploy, "deploy_succeeded")
    service.instance_variable_set(:@client, mock_client)
    service.deliver! # should not raise, just log
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/push_notification_service_test.rb`
Expected: FAIL — class doesn't exist yet

- [ ] **Step 3: Implement PushNotificationService**

Create `app/services/push_notification_service.rb`:

```ruby
class PushNotificationService
  TITLES = {
    "deploy_succeeded" => "Deploy Succeeded",
    "deploy_failed" => "Deploy Failed",
    "app_crashed" => "App Crashed",
    "backup_completed" => "Backup Completed",
    "backup_failed" => "Backup Failed"
  }.freeze

  CATEGORIES = {
    "deploy_succeeded" => "deploy",
    "deploy_failed" => "deploy",
    "app_crashed" => "alert",
    "backup_completed" => "backup",
    "backup_failed" => "alert"
  }.freeze

  def initialize(notification, deploy, event)
    @notification = notification
    @deploy = deploy
    @event = event
    @client = Expo::Push::Client.new
  end

  def deliver!
    tokens = device_tokens
    return if tokens.empty?

    messages = tokens.map { |dt| build_message(dt) }
    tickets = @client.publish(messages)

    tickets.each_with_index do |ticket, i|
      next unless ticket.id.present?
      PushTicket.create!(
        device_token: tokens[i],
        ticket_id: ticket.id,
        status: ticket.status
      )
    end
  rescue StandardError => e
    Rails.logger.warn("Push notification failed: #{e.message}")
  end

  private

  def device_tokens
    user_ids = @notification.team.users.pluck(:id)
    DeviceToken.where(user_id: user_ids)
  end

  def build_message(device_token)
    app = @deploy.app_record
    {
      to: device_token.token,
      title: TITLES[@event] || @event.titleize,
      body: build_body(app),
      data: {
        type: "deploy",
        app_id: app.id,
        deploy_id: @deploy.id,
        event: @event
      },
      sound: "default",
      categoryId: CATEGORIES[@event] || "default"
    }
  end

  def build_body(app)
    commit = @deploy.commit_sha&.first(7)
    version = @deploy.release&.version

    case @event
    when "deploy_succeeded"
      "#{app.name} deployed successfully#{commit ? " (#{commit})" : ""}#{version ? " v#{version}" : ""}"
    when "deploy_failed"
      "#{app.name} deploy failed#{commit ? " (#{commit})" : ""}"
    when "app_crashed"
      "#{app.name} has crashed"
    when "backup_completed"
      "#{app.name} backup completed"
    when "backup_failed"
      "#{app.name} backup failed"
    else
      "#{app.name}: #{@event.humanize}"
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/push_notification_service_test.rb`
Expected: All 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add app/services/push_notification_service.rb test/services/push_notification_service_test.rb
git commit -m "feat: PushNotificationService — delivers via Expo Push API"
```

---

### Task 4: Add push channel to NotifyJob

**Files:**
- Modify: `app/jobs/notify_job.rb:10-21`
- Modify: `test/jobs/notify_job_test.rb`

- [ ] **Step 1: Add push case to NotifyJob**

Add after the `when "telegram"` case (line 20) in `app/jobs/notify_job.rb`:

```ruby
    when "push"
      PushNotificationService.new(notification, deploy, event).deliver!
```

- [ ] **Step 2: Write test for push channel**

Add to `test/jobs/notify_job_test.rb`:

```ruby
  test "push channel delegates to PushNotificationService" do
    notification = Notification.create!(
      team: @team,
      channel: :push,
      events: ["deploy_succeeded"]
    )
    device = DeviceToken.create!(
      user: @user,
      token: "ExponentPushToken[notify-test-#{SecureRandom.hex(8)}]",
      platform: "ios"
    )

    # Stub Expo client to capture calls
    sent = []
    original_new = Expo::Push::Client.method(:new)
    mock_client = Object.new
    mock_client.define_singleton_method(:publish) do |msgs|
      sent.concat(msgs)
      msgs.map { |_| Expo::Push::Ticket.new("id" => "t-#{SecureRandom.hex}", "status" => "ok") }
    end
    Expo::Push::Client.define_singleton_method(:new) { |*_| mock_client }

    NotifyJob.perform_now(notification.id, "deploy_succeeded", @deploy.id)

    assert_equal 1, sent.size
    assert_equal device.token, sent.first[:to]
  ensure
    Expo::Push::Client.define_singleton_method(:new, original_new) if original_new
  end
```

- [ ] **Step 3: Run test**

Run: `bin/rails test test/jobs/notify_job_test.rb`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add app/jobs/notify_job.rb test/jobs/notify_job_test.rb
git commit -m "feat: add push channel to NotifyJob"
```

---

### Task 5: Notifiable concern + wire into deploy jobs

**Files:**
- Create: `app/concerns/notifiable.rb`
- Modify: `app/jobs/deploy_job.rb`
- Modify: `app/jobs/github_deploy_job.rb`
- Create: `test/concerns/notifiable_test.rb`

- [ ] **Step 1: Create Notifiable concern**

Create `app/concerns/notifiable.rb`:

```ruby
module Notifiable
  extend ActiveSupport::Concern

  private

  def fire_notifications(team, event, deploy)
    return unless team

    Notification.where(team: team).find_each do |notification|
      NotifyJob.perform_later(notification.id, event, deploy.id)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire notifications: #{e.message}")
  end
end
```

- [ ] **Step 2: Include in ApplicationJob**

Add to `app/jobs/application_job.rb` after line 1:

```ruby
  include Notifiable
```

- [ ] **Step 3: Wire into DeployJob**

In `app/jobs/deploy_job.rb`, add after line 29 (after `DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })`):

```ruby
    fire_notifications(app.team, "deploy_succeeded", deploy)
```

Add after line 37 (inside the `rescue Dokku::Client::CommandError` block, after the broadcast):

```ruby
    fire_notifications(app.team, "deploy_failed", deploy)
```

- [ ] **Step 4: Wire into GithubDeployJob**

In `app/jobs/github_deploy_job.rb`, add after line 31 (after succeeded broadcast):

```ruby
    fire_notifications(app.team, "deploy_succeeded", deploy)
```

Add after line 40 (inside the `rescue Dokku::Client::CommandError` block, after the broadcast):

```ruby
    fire_notifications(app.team, "deploy_failed", deploy)
```

- [ ] **Step 5: Write test for Notifiable concern**

Create `test/concerns/notifiable_test.rb`:

```ruby
require "test_helper"

class NotifiableTest < ActiveSupport::TestCase
  class TestJob < ApplicationJob
    include Notifiable
    public :fire_notifications
  end

  setup do
    @user = users(:two)
    @team = teams(:two)
    @app = app_records(:two)
    @deploy = @app.deploys.create!(status: :succeeded, commit_sha: "abc1234")
  end

  test "fire_notifications enqueues NotifyJob for each notification" do
    Notification.create!(team: @team, channel: :push, events: ["deploy_succeeded"])
    Notification.create!(team: @team, channel: :slack, events: ["deploy_succeeded"], config: { "url" => "https://hooks.slack.com/test" })

    job = TestJob.new

    assert_enqueued_jobs 2, only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end

  test "fire_notifications does nothing when team has no notifications" do
    job = TestJob.new

    assert_no_enqueued_jobs only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end

  test "fire_notifications handles nil team gracefully" do
    job = TestJob.new
    job.fire_notifications(nil, "deploy_succeeded", @deploy) # should not raise
  end

  test "fire_notifications skips notifications not subscribed to event" do
    Notification.create!(team: @team, channel: :push, events: ["deploy_failed"])

    job = TestJob.new
    # This notification only listens for deploy_failed, not deploy_succeeded
    assert_enqueued_jobs 1, only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end
end
```

Wait — that last test will enqueue 1 job because `fire_notifications` enqueues for ALL notifications (the event filtering happens inside `NotifyJob#perform`). Let me fix:

```ruby
  test "fire_notifications enqueues for all notifications (event filtering happens in NotifyJob)" do
    Notification.create!(team: @team, channel: :push, events: ["deploy_failed"])

    job = TestJob.new
    assert_enqueued_jobs 1, only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails test test/concerns/notifiable_test.rb`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add app/concerns/notifiable.rb app/jobs/application_job.rb app/jobs/deploy_job.rb app/jobs/github_deploy_job.rb test/concerns/notifiable_test.rb
git commit -m "feat: Notifiable concern + wire notifications into deploy jobs"
```

---

### Task 6: PushReceiptCheckJob

**Files:**
- Create: `app/jobs/push_receipt_check_job.rb`
- Create: `test/jobs/push_receipt_check_job_test.rb`

- [ ] **Step 1: Write the test**

Create `test/jobs/push_receipt_check_job_test.rb`:

```ruby
require "test_helper"

class PushReceiptCheckJobTest < ActiveJob::TestCase
  setup do
    @user = users(:two)
    @device = DeviceToken.create!(user: @user, token: "ExponentPushToken[receipt-test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  test "deletes device token when receipt says DeviceNotRegistered" do
    ticket = PushTicket.create!(device_token: @device, ticket_id: "ticket-bad")

    mock_client = Object.new
    mock_client.define_singleton_method(:get_receipts) do |ids|
      ids.map { |id| Expo::Push::Receipt.new("id" => id, "status" => "error", "details" => { "error" => "DeviceNotRegistered" }) }
    end

    original_new = Expo::Push::Client.method(:new)
    Expo::Push::Client.define_singleton_method(:new) { |*_| mock_client }

    assert_difference "DeviceToken.count", -1 do
      PushReceiptCheckJob.perform_now
    end

    assert_not PushTicket.exists?(ticket.id)
  ensure
    Expo::Push::Client.define_singleton_method(:new, original_new) if original_new
  end

  test "marks ticket as checked on success" do
    ticket = PushTicket.create!(device_token: @device, ticket_id: "ticket-ok")

    mock_client = Object.new
    mock_client.define_singleton_method(:get_receipts) do |ids|
      ids.map { |id| Expo::Push::Receipt.new("id" => id, "status" => "ok") }
    end

    original_new = Expo::Push::Client.method(:new)
    Expo::Push::Client.define_singleton_method(:new) { |*_| mock_client }

    PushReceiptCheckJob.perform_now

    ticket.reload
    assert_not_nil ticket.checked_at
  ensure
    Expo::Push::Client.define_singleton_method(:new, original_new) if original_new
  end

  test "cleans up stale tickets older than 24 hours" do
    old_ticket = PushTicket.create!(device_token: @device, ticket_id: "ticket-old", checked_at: 2.days.ago, created_at: 2.days.ago)

    mock_client = Object.new
    mock_client.define_singleton_method(:get_receipts) { |_| [] }

    original_new = Expo::Push::Client.method(:new)
    Expo::Push::Client.define_singleton_method(:new) { |*_| mock_client }

    PushReceiptCheckJob.perform_now

    assert_not PushTicket.exists?(old_ticket.id)
  ensure
    Expo::Push::Client.define_singleton_method(:new, original_new) if original_new
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/push_receipt_check_job_test.rb`
Expected: FAIL — class doesn't exist

- [ ] **Step 3: Implement PushReceiptCheckJob**

Create `app/jobs/push_receipt_check_job.rb`:

```ruby
class PushReceiptCheckJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    client = Expo::Push::Client.new

    PushTicket.pending.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      ticket_ids = batch.map(&:ticket_id)
      receipts = client.get_receipts(ticket_ids)

      receipts.each_with_index do |receipt, i|
        ticket = batch[i]

        if receipt.status == "error" && receipt.details&.dig("error") == "DeviceNotRegistered"
          ticket.device_token.destroy!
          Rails.logger.info("Removed invalid device token #{ticket.device_token_id}")
        else
          ticket.update!(checked_at: Time.current)
        end
      end
    end

    # Clean up stale tickets
    PushTicket.stale.delete_all
  rescue StandardError => e
    Rails.logger.warn("Push receipt check failed: #{e.message}")
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/push_receipt_check_job_test.rb`
Expected: All 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add app/jobs/push_receipt_check_job.rb test/jobs/push_receipt_check_job_test.rb
git commit -m "feat: PushReceiptCheckJob — cleans up invalid device tokens"
```

---

### Task 7: Run full suite and verify

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test --seed 12345`
Expected: All pass (0 failures)

- [ ] **Step 2: Run rubocop**

Run: `bundle exec rubocop app/services/push_notification_service.rb app/jobs/push_receipt_check_job.rb app/concerns/notifiable.rb app/jobs/notify_job.rb app/jobs/deploy_job.rb app/jobs/github_deploy_job.rb app/models/push_ticket.rb`
Expected: 0 offenses

- [ ] **Step 3: Fix any rubocop issues if found**

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "chore: rubocop fixes for push notification code"
```
