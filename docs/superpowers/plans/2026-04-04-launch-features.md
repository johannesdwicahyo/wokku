# Launch Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 6 features to close gaps vs Heroku and Coolify before public launch.

**Architecture:** Each feature is independent. Features 1-5 are backend+frontend changes following existing patterns. Feature 6 is a QA script. All features include tests.

**Tech Stack:** Rails 8.1, Dokku CLI wrapping, Minitest, ERB views

---

## Feature 1: PR Preview / Review Apps UI

### Task 1.1: Migration + Model Changes

**Files:**
- Create: `db/migrate/XXXXXX_add_preview_fields_to_app_records.rb`
- Modify: `app/models/app_record.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration AddPreviewFieldsToAppRecords is_preview:boolean pr_number:integer parent_app_id:integer`

- [ ] **Step 2: Edit migration**

```ruby
class AddPreviewFieldsToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :is_preview, :boolean, default: false, null: false
    add_column :app_records, :pr_number, :integer
    add_reference :app_records, :parent_app, foreign_key: { to_table: :app_records }, null: true
    add_index :app_records, [:parent_app_id, :pr_number], unique: true, where: "is_preview = true"
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 4: Update AppRecord model**

Add to `app/models/app_record.rb`:

```ruby
  belongs_to :parent_app, class_name: "AppRecord", optional: true
  has_many :preview_apps, class_name: "AppRecord", foreign_key: :parent_app_id, dependent: :destroy

  scope :main_apps, -> { where(is_preview: false) }
  scope :previews, -> { where(is_preview: true) }
```

- [ ] **Step 5: Update PrPreviewDeployJob**

In `app/jobs/pr_preview_deploy_job.rb`, add preview fields when creating the app (around line 18-26):

After `app.assign_attributes(...)`, add:
```ruby
      is_preview: true,
      pr_number: pr_number,
      parent_app_id: parent_app.id,
```

- [ ] **Step 6: Update dashboard apps controller**

In `app/controllers/dashboard/apps_controller.rb`, filter previews from main index. Change the `index` query to use `.main_apps` scope.

- [ ] **Step 7: Add preview apps section to app detail view**

Read `app/views/dashboard/apps/show.html.erb`. Add a "Preview Apps" section that lists `@app.preview_apps` with PR number, status, and link to GitHub PR.

- [ ] **Step 8: Update API apps controller**

In `app/controllers/api/v1/apps_controller.rb`, filter previews from index by default. Add `params[:include_previews]` to include them.

- [ ] **Step 9: Write tests**

Create `test/models/app_record_preview_test.rb`:
- Test `main_apps` scope excludes previews
- Test `previews` scope returns only previews
- Test `preview_apps` association
- Test `parent_app` association

- [ ] **Step 10: Run tests and commit**

Run: `bin/rails test test/models/app_record_preview_test.rb`

```bash
git add -A && git commit -m "feat: PR preview apps — model, migration, dashboard UI, API filter"
```

---

## Feature 2: Log Drains

### Task 2.1: LogDrain Model + Dokku Service

**Files:**
- Create: `db/migrate/XXXXXX_create_log_drains.rb`
- Create: `app/models/log_drain.rb`
- Create: `app/services/dokku/log_drains.rb`
- Create: `app/controllers/dashboard/log_drains_controller.rb`
- Create: `app/controllers/api/v1/log_drains_controller.rb`
- Create: `test/services/dokku/log_drains_test.rb`
- Create: `test/controllers/dashboard/log_drains_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Generate model**

Run: `bin/rails generate model LogDrain app_record:references url:string drain_type:string`

- [ ] **Step 2: Edit migration**

```ruby
class CreateLogDrains < ActiveRecord::Migration[8.1]
  def change
    create_table :log_drains do |t|
      t.references :app_record, null: false, foreign_key: true
      t.string :url, null: false
      t.string :drain_type, default: "syslog"
      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 3: Create LogDrain model**

```ruby
class LogDrain < ApplicationRecord
  belongs_to :app_record

  validates :url, presence: true, format: { with: /\A(syslog|https?):\/\/.+\z/, message: "must be a valid syslog or HTTP URL" }
  validates :drain_type, inclusion: { in: %w[syslog https] }
end
```

Add to `app/models/app_record.rb`:
```ruby
  has_many :log_drains, dependent: :destroy
```

- [ ] **Step 4: Create Dokku::LogDrains service**

Create `app/services/dokku/log_drains.rb`:

```ruby
module Dokku
  class LogDrains
    def initialize(client)
      @client = client
    end

    def add(app_name, url)
      @client.run("docker-options:add #{app_name} deploy,run \"--log-driver syslog --log-opt syslog-address=#{url}\"")
    end

    def remove(app_name)
      @client.run("docker-options:remove #{app_name} deploy,run \"--log-driver syslog\"") rescue nil
    end

    def report(app_name)
      output = @client.run("docker-options:report #{app_name}")
      output.to_s
    end
  end
end
```

- [ ] **Step 5: Create dashboard controller**

Create `app/controllers/dashboard/log_drains_controller.rb` with `create` and `destroy` actions. Nested under apps.

- [ ] **Step 6: Add routes**

Add to `config/routes.rb` inside the dashboard `resources :apps` block:
```ruby
resources :log_drains, only: [:create, :destroy]
```

Add to API routes inside `resources :apps`:
```ruby
resources :log_drains, only: [:index, :create, :destroy]
```

- [ ] **Step 7: Add UI to logs page**

Add a "Log Drains" section to the app logs view showing existing drains and an add form.

- [ ] **Step 8: Write tests**

Test the Dokku service with MockClient, test controller auth + CRUD.

- [ ] **Step 9: Run tests and commit**

```bash
git add -A && git commit -m "feat: log drains — forward app logs to external services"
```

---

## Feature 3: Resource Threshold Alerts

### Task 3.1: Extend MetricsPollJob + Notification Events

**Files:**
- Modify: `app/jobs/metrics_poll_job.rb`
- Modify: `app/concerns/notifiable.rb`
- Create: `test/jobs/metrics_poll_alert_test.rb`

- [ ] **Step 1: Refactor Notifiable concern to support non-deploy events**

Currently `fire_notifications` requires a `deploy`. Overload it to accept app-only context:

In `app/concerns/notifiable.rb`, add a second method:

```ruby
  def fire_app_notifications(team, event, app_record)
    return unless team

    Notification.where(team: team).find_each do |notification|
      next unless notification.events.include?(event)

      # For non-deploy events, create a minimal deploy-like record or refactor NotifyJob
      # Simplest: create a "virtual" deploy for the notification
      deploy = app_record.deploys.create!(status: :succeeded, commit_sha: "system")
      NotifyJob.perform_later(notification.id, event, deploy.id)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire app notifications: #{e.message}")
  end
```

- [ ] **Step 2: Extend MetricsPollJob with threshold checking**

Add at the end of `perform`, after collecting metrics, inside the `output.each_line` block:

```ruby
      # Check thresholds
      cpu = data["CPUPerc"].to_f
      mem_pct = app.metrics.last&.memory_usage.to_f / app.metrics.last&.memory_limit.to_f * 100 rescue 0

      check_threshold(app, "resource_high_cpu", cpu, 80.0)
      check_threshold(app, "resource_high_memory", mem_pct, 90.0)
```

Add private method:

```ruby
  def check_threshold(app, event, value, threshold)
    cache_key = "alert:#{app.id}:#{event}"

    if value > threshold
      count = Rails.cache.increment(cache_key, 1, expires_in: 1.hour)
      if count == 2 # Fire after 2 consecutive polls above threshold
        fire_app_notifications(app.team, event, app)
        Rails.cache.write(cache_key, 0, expires_in: 1.hour) # Reset after firing
      end
    else
      Rails.cache.delete(cache_key)
    end
  end
```

- [ ] **Step 3: Add Notifiable to MetricsPollJob**

Add `include Notifiable` at the top of `MetricsPollJob`.

- [ ] **Step 4: Update PushNotificationService**

Add new event titles and categories to `TITLES` and `CATEGORIES` in `app/services/push_notification_service.rb`:

```ruby
    "resource_high_cpu" => "High CPU Alert",
    "resource_high_memory" => "High Memory Alert",
```

And categories:
```ruby
    "resource_high_cpu" => "alert",
    "resource_high_memory" => "alert",
```

Also update `build_body` to handle these events.

- [ ] **Step 5: Update NotifyJob build_message**

Add cases in `app/jobs/notify_job.rb` `build_message` method:

```ruby
    when "resource_high_cpu"
      "#{app_name} CPU usage is above 80%"
    when "resource_high_memory"
      "#{app_name} memory usage is above 90%"
```

- [ ] **Step 6: Write tests**

Test threshold detection with mocked metrics data.

- [ ] **Step 7: Run tests and commit**

```bash
git add -A && git commit -m "feat: resource threshold alerts — notify on high CPU/memory"
```

---

## Feature 4: Health Checks UI

### Task 4.1: Dokku::Checks Service + Dashboard UI

**Files:**
- Create: `app/services/dokku/checks.rb`
- Create: `app/controllers/dashboard/checks_controller.rb`
- Create: `app/controllers/api/v1/checks_controller.rb`
- Create: `test/services/dokku/checks_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Create Dokku::Checks service**

Create `app/services/dokku/checks.rb`:

```ruby
module Dokku
  class Checks
    def initialize(client)
      @client = client
    end

    def report(app_name)
      output = @client.run("checks:report #{app_name}")
      parse_report(output)
    end

    def enable(app_name)
      @client.run("checks:enable #{app_name}")
    end

    def disable(app_name)
      @client.run("checks:disable #{app_name}")
    end

    def set(app_name, key, value)
      @client.run("checks:set #{app_name} #{key} #{value}")
    end

    private

    def parse_report(output)
      result = {}
      output.to_s.each_line do |line|
        next unless line.include?(":")
        key, value = line.split(":", 2).map(&:strip)
        next if key.blank?
        normalized = key.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
        result[normalized] = value
      end
      result
    end
  end
end
```

- [ ] **Step 2: Create dashboard controller**

Create `app/controllers/dashboard/checks_controller.rb` with `show` and `update` actions. Reads report from Dokku, allows enable/disable and setting check path/timeout.

- [ ] **Step 3: Add routes**

Dashboard: `resource :checks, only: [:show, :update]` nested under apps.
API: `resource :checks, only: [:show, :update]` nested under apps.

- [ ] **Step 4: Add UI to app detail page**

Add "Health Checks" card showing enabled/disabled toggle, check path, wait time, timeout, attempts. Edit form for changing settings.

- [ ] **Step 5: Write tests with MockClient**

- [ ] **Step 6: Run tests and commit**

```bash
git add -A && git commit -m "feat: health checks UI — configure Dokku checks from dashboard"
```

---

## Feature 5: GitLab/Bitbucket Integration

### Task 5.1: Generalize Git Provider + Webhook Controllers

**Files:**
- Create: `db/migrate/XXXXXX_add_git_provider_to_app_records.rb`
- Create: `app/controllers/webhooks/gitlab_controller.rb`
- Create: `app/controllers/webhooks/bitbucket_controller.rb`
- Create: `app/jobs/gitlab_deploy_job.rb`
- Create: `app/jobs/bitbucket_deploy_job.rb`
- Create: `test/controllers/webhooks/gitlab_controller_test.rb`
- Create: `test/controllers/webhooks/bitbucket_controller_test.rb`
- Modify: `config/routes.rb`
- Modify: `app/models/app_record.rb`

- [ ] **Step 1: Migration**

```ruby
class AddGitProviderToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :git_provider, :string
    add_column :app_records, :git_repo_full_name, :string
    add_column :app_records, :git_webhook_secret, :string
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Create GitLab webhook controller**

Create `app/controllers/webhooks/gitlab_controller.rb`:

```ruby
module Webhooks
  class GitlabController < ActionController::API
    before_action :verify_token!

    def create
      event = request.headers["X-Gitlab-Event"]

      case event
      when "Push Hook"
        handle_push(JSON.parse(request.body.read))
      when "Merge Request Hook"
        handle_merge_request(JSON.parse(request.body.read))
      end

      head :ok
    end

    private

    def verify_token!
      token = request.headers["X-Gitlab-Token"]
      secret = params[:secret] || ENV["GITLAB_WEBHOOK_SECRET"]
      head :unauthorized unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, secret.to_s)
    end

    def handle_push(payload)
      ref = payload["ref"]
      branch = ref&.sub("refs/heads/", "")
      repo_url = payload.dig("project", "git_http_url")
      repo_path = payload.dig("project", "path_with_namespace")
      commit_sha = payload.dig("checkout_sha")
      commit_message = payload.dig("commits", 0, "message")

      return unless repo_path && branch

      apps = AppRecord.where(git_provider: "gitlab", git_repo_full_name: repo_path, deploy_branch: branch)

      apps.find_each do |app|
        deploy = app.deploys.create!(status: :pending, commit_sha: commit_sha)
        release = app.releases.create!(
          version: (app.releases.maximum(:version) || 0) + 1,
          deploy: deploy,
          description: commit_message&.truncate(200)
        )
        GitlabDeployJob.perform_later(
          app_id: app.id, deploy_id: deploy.id,
          repo_url: repo_url, branch: branch, commit_sha: commit_sha
        )
      end
    end

    def handle_merge_request(payload)
      # PR preview support for GitLab — same pattern as GitHub
      action = payload.dig("object_attributes", "action")
      return unless %w[open reopen update close merge].include?(action)
      # Implementation follows same pattern as GitHub PR handler
      head :ok
    end
  end
end
```

- [ ] **Step 3: Create Bitbucket webhook controller**

Create `app/controllers/webhooks/bitbucket_controller.rb` — similar structure, different payload format. Bitbucket sends `repo:push` and `pullrequest:*` events.

- [ ] **Step 4: Create deploy jobs**

Create `app/jobs/gitlab_deploy_job.rb` and `app/jobs/bitbucket_deploy_job.rb` — same pattern as `GithubDeployJob` but use the provider-specific repo URL.

- [ ] **Step 5: Add routes**

```ruby
post "/webhooks/gitlab", to: "webhooks/gitlab#create"
post "/webhooks/bitbucket", to: "webhooks/bitbucket#create"
```

- [ ] **Step 6: Update app settings view**

Add provider selector (GitHub / GitLab / Bitbucket) to the repository connection UI in app settings.

- [ ] **Step 7: Write tests**

Test webhook signature verification, push event handling, deploy job enqueueing.

- [ ] **Step 8: Run tests and commit**

```bash
git add -A && git commit -m "feat: GitLab and Bitbucket webhook integration"
```

---

## Feature 6: Template Validation

### Task 6.1: Validation Script

**Files:**
- Create: `bin/validate-templates`
- Create: `test/services/template_validation_test.rb`

- [ ] **Step 1: Create light validation script**

Create `bin/validate-templates`:

```bash
#!/usr/bin/env ruby
require_relative "../config/environment"

puts "=== Template Validation ==="
puts ""

registry = TemplateRegistry.new
templates = registry.all
passed = 0
failed = 0
errors = []

templates.each do |template|
  checks = []

  # Check required fields
  checks << ["name present", template[:name].present?]
  checks << ["slug present", template[:slug].present?]
  checks << ["description present", template[:description].present?]
  checks << ["category present", template[:category].present?]

  # Check template file exists and is parseable
  template_path = Rails.root.join("app/templates", template[:slug], "docker-compose.yml")
  checks << ["docker-compose.yml exists", File.exist?(template_path)]

  if File.exist?(template_path)
    begin
      content = File.read(template_path)
      # Check for valid image reference
      has_image = content.include?("image:")
      checks << ["has image reference", has_image]

      # Check for port mapping
      has_ports = content.include?("ports:")
      checks << ["has port mapping", has_ports]
    rescue => e
      checks << ["parseable", false]
    end
  end

  all_passed = checks.all? { |_, ok| ok }

  if all_passed
    puts "  ✓ #{template[:name]} (#{template[:slug]})"
    passed += 1
  else
    puts "  ✗ #{template[:name]} (#{template[:slug]})"
    checks.reject { |_, ok| ok }.each { |check, _| puts "    - FAIL: #{check}" }
    failed += 1
    errors << { template: template[:slug], failures: checks.reject { |_, ok| ok }.map(&:first) }
  end
end

puts ""
puts "=== Results ==="
puts "Total: #{templates.size}"
puts "Passed: #{passed}"
puts "Failed: #{failed}"
puts ""

if failed > 0
  puts "Failed templates:"
  errors.each { |e| puts "  #{e[:template]}: #{e[:failures].join(', ')}" }
  exit 1
else
  puts "All templates validated!"
end
```

- [ ] **Step 2: Make executable**

Run: `chmod +x bin/validate-templates`

- [ ] **Step 3: Create test**

Create `test/services/template_validation_test.rb`:

```ruby
require "test_helper"

class TemplateValidationTest < ActiveSupport::TestCase
  test "all templates have required fields" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      assert template[:name].present?, "#{template[:slug]} missing name"
      assert template[:slug].present?, "#{template[:slug]} missing slug"
      assert template[:category].present?, "#{template[:slug] || 'unknown'} missing category"
    end
  end

  test "all templates have docker-compose.yml" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      path = Rails.root.join("app/templates", template[:slug], "docker-compose.yml")
      assert File.exist?(path), "#{template[:slug]} missing docker-compose.yml"
    end
  end

  test "all template docker-compose files have image references" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      path = Rails.root.join("app/templates", template[:slug], "docker-compose.yml")
      next unless File.exist?(path)
      content = File.read(path)
      assert content.include?("image:"), "#{template[:slug]} docker-compose.yml has no image reference"
    end
  end
end
```

- [ ] **Step 4: Run validation**

Run: `bin/validate-templates`
Run: `bin/rails test test/services/template_validation_test.rb`

Fix any broken templates found.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: template validation script + tests"
```

---

## Execution Order

All 6 features are independent. Recommended parallel execution:

- **Batch 1:** Feature 1 (PR Previews) + Feature 6 (Template Validation) — low risk
- **Batch 2:** Feature 2 (Log Drains) + Feature 4 (Health Checks) — new Dokku wrappers
- **Batch 3:** Feature 3 (Resource Alerts) + Feature 5 (GitLab/Bitbucket) — more complex

## Final Verification

After all features:
- [ ] `bin/rails test --seed 12345` — all pass
- [ ] `bundle exec rubocop` — 0 offenses
- [ ] `bin/validate-templates` — all 50 templates pass
- [ ] Deploy: `kamal deploy`
