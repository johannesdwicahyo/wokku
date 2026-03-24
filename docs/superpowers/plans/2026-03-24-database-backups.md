# Database Backups to S3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automated and on-demand database backups to any S3-compatible storage (AWS S3, Cloudflare R2, MinIO, Backblaze B2, DigitalOcean Spaces, Wasabi) with browse, download, and restore capabilities.

**Architecture:** Each server has encrypted S3 credentials. A daily `BackupSchedulerJob` iterates all databases on backup-enabled servers, runs the appropriate Dokku export command via SSH, pipes the gzipped output to S3 via `aws-sdk-s3`. A `Backup` model tracks metadata. Users browse backups from the database detail page, trigger on-demand backups, and restore with one click. A retention job deletes old backups.

**Tech Stack:** aws-sdk-s3 gem, Dokku export/import commands via SSH, Solid Queue, Active Record Encryption

---

## File Structure

### New Files

```
app/models/backup.rb                                  — Backup record (database, S3 key, size, status)
app/models/backup_destination.rb                       — S3 credentials per server (encrypted)
app/services/backup_service.rb                         — Dump database + upload to S3
app/services/restore_service.rb                        — Download from S3 + import into database
app/jobs/backup_job.rb                                 — Backup a single database
app/jobs/backup_scheduler_job.rb                       — Schedule daily backups for all databases
app/jobs/backup_retention_job.rb                       — Delete expired backups
app/controllers/dashboard/backups_controller.rb        — Browse, create, download, restore
app/controllers/dashboard/backup_destinations_controller.rb — Configure S3 settings
app/views/dashboard/backups/index.html.erb             — Backup list per database
app/views/dashboard/backup_destinations/edit.html.erb  — S3 config form
db/migrate/TIMESTAMP_create_backups.rb
db/migrate/TIMESTAMP_create_backup_destinations.rb
test/models/backup_test.rb
test/services/backup_service_test.rb
```

### Modified Files

```
Gemfile                                                — Add aws-sdk-s3
app/views/dashboard/databases/show.html.erb            — Add "Backups" section
app/views/dashboard/servers/show.html.erb              — Add backup destination config link
config/routes.rb                                       — Add backup and destination routes
config/recurring.yml                                   — Add backup scheduler job
```

---

## Task 1: Add aws-sdk-s3 Gem and Migrations

**Files:**
- Modify: `Gemfile`
- Create: `db/migrate/20260324000002_create_backup_destinations.rb`
- Create: `db/migrate/20260324000003_create_backups.rb`

- [ ] **Step 1: Add gem**

Add to `Gemfile` after the GitHub section:

```ruby
# S3 Backups (supports AWS S3, Cloudflare R2, MinIO, Backblaze B2, DO Spaces)
gem "aws-sdk-s3", require: false
```

Run: `bundle install`

- [ ] **Step 2: Create backup destinations migration**

```ruby
# db/migrate/20260324000002_create_backup_destinations.rb
class CreateBackupDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_destinations do |t|
      t.references :server, null: false, foreign_key: true
      t.string :provider, default: "s3"           # s3, r2, minio, b2, spaces
      t.string :endpoint_url                       # custom endpoint for non-AWS
      t.string :bucket, null: false
      t.string :region, default: "us-east-1"
      t.string :access_key_id
      t.string :secret_access_key
      t.string :path_prefix, default: "wokku-backups"
      t.integer :retention_days, default: 30
      t.boolean :enabled, default: true
      t.timestamps
    end
    add_index :backup_destinations, :server_id, unique: true
  end
end
```

- [ ] **Step 3: Create backups migration**

```ruby
# db/migrate/20260324000003_create_backups.rb
class CreateBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :backups do |t|
      t.references :database_service, null: false, foreign_key: true
      t.references :backup_destination, null: false, foreign_key: true
      t.string :s3_key, null: false
      t.string :status, default: "pending"        # pending, running, completed, failed
      t.bigint :size_bytes
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :backups, [:database_service_id, :created_at]
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate/20260324000002_create_backup_destinations.rb db/migrate/20260324000003_create_backups.rb
git commit -m "feat: add aws-sdk-s3 gem and backup migrations"
```

---

## Task 2: Backup Destination and Backup Models

**Files:**
- Create: `app/models/backup_destination.rb`
- Create: `app/models/backup.rb`
- Modify: `app/models/server.rb`
- Modify: `app/models/database_service.rb`
- Create: `test/models/backup_test.rb`

- [ ] **Step 1: Write models**

```ruby
# app/models/backup_destination.rb
class BackupDestination < ApplicationRecord
  belongs_to :server
  has_many :backups, dependent: :destroy

  encrypts :access_key_id
  encrypts :secret_access_key

  validates :bucket, presence: true

  PROVIDERS = {
    "s3" => { name: "Amazon S3", endpoint: nil },
    "r2" => { name: "Cloudflare R2", endpoint_hint: "https://<account_id>.r2.cloudflarestorage.com" },
    "minio" => { name: "MinIO", endpoint_hint: "http://minio.example.com:9000" },
    "b2" => { name: "Backblaze B2", endpoint_hint: "https://s3.<region>.backblazeb2.com" },
    "spaces" => { name: "DigitalOcean Spaces", endpoint_hint: "https://<region>.digitaloceanspaces.com" },
    "wasabi" => { name: "Wasabi", endpoint_hint: "https://s3.<region>.wasabisys.com" }
  }.freeze

  def s3_client
    require "aws-sdk-s3"
    config = {
      region: region || "us-east-1",
      credentials: Aws::Credentials.new(access_key_id, secret_access_key)
    }
    config[:endpoint] = endpoint_url if endpoint_url.present?
    config[:force_path_style] = true if endpoint_url.present? # Required for MinIO, R2, etc.
    Aws::S3::Client.new(config)
  end

  def s3_presigned_url(key, expires_in: 3600)
    require "aws-sdk-s3"
    signer = Aws::S3::Presigner.new(client: s3_client)
    signer.presigned_url(:get_object, bucket: bucket, key: key, expires_in: expires_in)
  end
end
```

```ruby
# app/models/backup.rb
class Backup < ApplicationRecord
  belongs_to :database_service
  belongs_to :backup_destination

  scope :completed, -> { where(status: "completed") }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def size_human
    return "—" unless size_bytes
    if size_bytes < 1024
      "#{size_bytes} B"
    elsif size_bytes < 1024 * 1024
      "#{(size_bytes / 1024.0).round(1)} KB"
    elsif size_bytes < 1024 * 1024 * 1024
      "#{(size_bytes / (1024.0 * 1024)).round(1)} MB"
    else
      "#{(size_bytes / (1024.0 * 1024 * 1024)).round(2)} GB"
    end
  end

  def download_url(expires_in: 3600)
    backup_destination.s3_presigned_url(s3_key, expires_in: expires_in)
  end

  def expired?(retention_days = nil)
    days = retention_days || backup_destination.retention_days
    created_at < days.days.ago
  end
end
```

- [ ] **Step 2: Update existing models**

Add to `app/models/server.rb`:
```ruby
has_one :backup_destination, dependent: :destroy
```

Add to `app/models/database_service.rb`:
```ruby
has_many :backups, dependent: :destroy
```

- [ ] **Step 3: Write test**

```ruby
# test/models/backup_test.rb
require "test_helper"

class BackupTest < ActiveSupport::TestCase
  test "size_human formats bytes correctly" do
    backup = Backup.new(size_bytes: 1024)
    assert_equal "1.0 KB", backup.size_human

    backup.size_bytes = 5 * 1024 * 1024
    assert_equal "5.0 MB", backup.size_human
  end

  test "expired? checks retention days" do
    dest = BackupDestination.new(retention_days: 7)
    backup = Backup.new(backup_destination: dest, created_at: 8.days.ago)
    assert backup.expired?

    backup.created_at = 3.days.ago
    assert_not backup.expired?
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add app/models/backup_destination.rb app/models/backup.rb app/models/server.rb app/models/database_service.rb test/models/backup_test.rb
git commit -m "feat: add Backup and BackupDestination models with S3 support"
```

---

## Task 3: BackupService (Dump + Upload)

**Files:**
- Create: `app/services/backup_service.rb`
- Create: `test/services/backup_service_test.rb`

- [ ] **Step 1: Write test**

```ruby
# test/services/backup_service_test.rb
require "test_helper"

class BackupServiceTest < ActiveSupport::TestCase
  test "export_command returns correct command for postgres" do
    db = DatabaseService.new(name: "my-db", service_type: "postgres")
    service = BackupService.new(db)
    assert_equal "postgres:export my-db", service.send(:export_command)
  end

  test "export_command returns correct command for mysql" do
    db = DatabaseService.new(name: "my-db", service_type: "mysql")
    service = BackupService.new(db)
    assert_equal "mysql:export my-db", service.send(:export_command)
  end

  test "s3_key generates timestamped path" do
    db = DatabaseService.new(name: "my-db", service_type: "postgres")
    service = BackupService.new(db)
    key = service.send(:generate_s3_key, "wokku-backups")
    assert_match %r{wokku-backups/postgres/my-db/\d{4}-\d{2}-\d{2}}, key
  end
end
```

- [ ] **Step 2: Write the service**

```ruby
# app/services/backup_service.rb
class BackupService
  EXPORT_COMMANDS = {
    "postgres" => "postgres:export",
    "mysql" => "mysql:export",
    "mariadb" => "mariadb:export",
    "mongodb" => "mongo:export",
    "redis" => "redis:export"
  }.freeze

  def initialize(database_service)
    @db = database_service
    @server = database_service.server
  end

  def perform!
    destination = @server.backup_destination
    raise "No backup destination configured for #{@server.name}" unless destination

    backup = @db.backups.create!(
      backup_destination: destination,
      status: "running",
      started_at: Time.current,
      s3_key: generate_s3_key(destination.path_prefix)
    )

    begin
      # Dump database via Dokku SSH to a local tempfile
      client = Dokku::Client.new(@server)
      raw_tempfile = Tempfile.new(["backup_raw", ".dump"], binmode: true)
      gz_tempfile = Tempfile.new(["backup", ".gz"], binmode: true)

      # Stream export output to tempfile (binary mode)
      client.run_streaming(export_command) do |data|
        raw_tempfile.write(data)
      end
      raw_tempfile.rewind

      # Compress with gzip in Ruby
      Zlib::GzipWriter.open(gz_tempfile.path) do |gz|
        while (chunk = raw_tempfile.read(64 * 1024))
          gz.write(chunk)
        end
      end
      gz_tempfile.rewind

      # Upload to S3
      destination.s3_client.put_object(
        bucket: destination.bucket,
        key: backup.s3_key,
        body: File.open(gz_tempfile.path, "rb"),
        content_type: "application/gzip"
      )

      backup.update!(
        status: "completed",
        size_bytes: File.size(gz_tempfile.path),
        completed_at: Time.current
      )

      backup
    rescue => e
      backup.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )
      raise
    ensure
      raw_tempfile&.close; raw_tempfile&.unlink
      gz_tempfile&.close; gz_tempfile&.unlink
    end
  end

  private

  def export_command
    cmd = EXPORT_COMMANDS[@db.service_type]
    raise "Unsupported database type for backup: #{@db.service_type}" unless cmd
    "#{cmd} #{@db.name}"
  end

  def generate_s3_key(prefix)
    timestamp = Time.current.strftime("%Y-%m-%d_%H%M%S")
    "#{prefix}/#{@db.service_type}/#{@db.name}/#{timestamp}.gz"
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/backup_service.rb test/services/backup_service_test.rb
git commit -m "feat: add BackupService for database dump and S3 upload"
```

---

## Task 4: RestoreService

**Files:**
- Create: `app/services/restore_service.rb`

- [ ] **Step 1: Write the service**

```ruby
# app/services/restore_service.rb
class RestoreService
  IMPORT_COMMANDS = {
    "postgres" => "postgres:import",
    "mysql" => "mysql:import",
    "mariadb" => "mariadb:import",
    "mongodb" => "mongo:import",
    "redis" => "redis:import"
  }.freeze

  def initialize(backup)
    @backup = backup
    @db = backup.database_service
    @server = @db.server
    @destination = backup.backup_destination
  end

  def perform!
    cmd = IMPORT_COMMANDS[@db.service_type]
    raise "Unsupported database type for restore: #{@db.service_type}" unless cmd

    # Download from S3 to tempfile
    gz_tempfile = Tempfile.new(["restore", ".gz"], binmode: true)
    @destination.s3_client.get_object(
      bucket: @destination.bucket,
      key: @backup.s3_key,
      response_target: gz_tempfile.path
    )

    # Decompress and pipe into Dokku import via SSH stdin
    ssh_options = {
      port: @server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    ssh_options[:key_data] = [@server.ssh_private_key] if @server.ssh_private_key.present?

    ssh_user = @server.ssh_user || "dokku"
    import_cmd = ssh_user == "dokku" ? "#{cmd} #{@db.name}" : "dokku #{cmd} #{@db.name}"

    Net::SSH.start(@server.host, ssh_user, ssh_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(import_cmd) do |_ch, success|
          raise "Failed to execute import command" unless success

          # Stream decompressed data into SSH stdin
          Zlib::GzipReader.open(gz_tempfile.path) do |gz|
            while (chunk = gz.read(64 * 1024))
              ch.send_data(chunk)
            end
          end
          ch.eof!  # Signal end of input

          ch.on_extended_data { |_, _, data| Rails.logger.warn("Restore stderr: #{data}") }
        end
      end
      channel.wait
    end

    true
  rescue => e
    Rails.logger.error("RestoreService: Failed to restore #{@db.name}: #{e.message}")
    raise
  ensure
    gz_tempfile&.close
    gz_tempfile&.unlink
  end
end
```

Note: The restore command piping may need adjustment depending on Dokku's import interface. Some Dokku plugins accept piped stdin: `cat dump.gz | gunzip | dokku postgres:import db-name`. The SSH client may need to transfer the file first then run the import.

- [ ] **Step 2: Commit**

```bash
git add app/services/restore_service.rb
git commit -m "feat: add RestoreService for S3 download and database import"
```

---

## Task 5: Backup Jobs (Backup, Scheduler, Retention)

**Files:**
- Create: `app/jobs/backup_job.rb`
- Create: `app/jobs/backup_scheduler_job.rb`
- Create: `app/jobs/backup_retention_job.rb`
- Modify: `config/recurring.yml`

- [ ] **Step 1: Write backup job**

```ruby
# app/jobs/backup_job.rb
class BackupJob < ApplicationJob
  queue_as :backups

  def perform(database_service_id)
    db = DatabaseService.find(database_service_id)
    BackupService.new(db).perform!
    Rails.logger.info("BackupJob: Backed up #{db.name} (#{db.service_type})")
  rescue => e
    Rails.logger.error("BackupJob: Failed to backup #{database_service_id}: #{e.message}")
  end
end
```

- [ ] **Step 2: Write scheduler job**

```ruby
# app/jobs/backup_scheduler_job.rb
class BackupSchedulerJob < ApplicationJob
  queue_as :backups

  BACKUPABLE_TYPES = %w[postgres mysql mariadb mongodb redis].freeze

  def perform
    Server.joins(:backup_destination)
      .where(backup_destinations: { enabled: true })
      .find_each do |server|
        server.database_services
          .where(service_type: BACKUPABLE_TYPES, status: :running)
          .find_each do |db|
            BackupJob.perform_later(db.id)
          end
      end
  end
end
```

- [ ] **Step 3: Write retention job**

```ruby
# app/jobs/backup_retention_job.rb
class BackupRetentionJob < ApplicationJob
  queue_as :backups

  def perform
    BackupDestination.where(enabled: true).find_each do |dest|
      expired = Backup.where(backup_destination: dest, status: "completed")
        .where("created_at < ?", dest.retention_days.days.ago)

      expired.find_each do |backup|
        begin
          dest.s3_client.delete_object(bucket: dest.bucket, key: backup.s3_key)
          backup.destroy!
          Rails.logger.info("BackupRetentionJob: Deleted expired backup #{backup.s3_key}")
        rescue => e
          Rails.logger.error("BackupRetentionJob: Failed to delete #{backup.s3_key}: #{e.message}")
        end
      end
    end
  end
end
```

- [ ] **Step 4: Add to recurring.yml**

Add under the `production:` key in `config/recurring.yml`:

```yaml
  backup_scheduler:
    class: BackupSchedulerJob
    schedule: every day at 2am
    queue: backups

  backup_retention:
    class: BackupRetentionJob
    schedule: every day at 4am
    queue: backups
```

- [ ] **Step 5: Commit**

```bash
git add app/jobs/backup_job.rb app/jobs/backup_scheduler_job.rb app/jobs/backup_retention_job.rb config/recurring.yml
git commit -m "feat: add backup scheduler, retention, and individual backup jobs"
```

---

## Task 6: Backup Destination Config UI

**Files:**
- Create: `app/controllers/dashboard/backup_destinations_controller.rb`
- Create: `app/views/dashboard/backup_destinations/edit.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/dashboard/servers/show.html.erb`

- [ ] **Step 1: Write the controller**

```ruby
# app/controllers/dashboard/backup_destinations_controller.rb
module Dashboard
  class BackupDestinationsController < BaseController
    def edit
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination
    end

    def update
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination

      if @destination.update(destination_params)
        redirect_to dashboard_server_path(@server), notice: "Backup destination saved"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def destination_params
      params.require(:backup_destination).permit(
        :provider, :endpoint_url, :bucket, :region,
        :access_key_id, :secret_access_key, :path_prefix,
        :retention_days, :enabled
      )
    end
  end
end
```

- [ ] **Step 2: Write the config form view**

```erb
<%# app/views/dashboard/backup_destinations/edit.html.erb %>
<% content_for(:title, "Backup Settings — #{@server.name}") %>

<div class="max-w-2xl mx-auto space-y-6">
  <%= link_to dashboard_server_path(@server), class: "inline-flex items-center text-sm text-gray-500 hover:text-gray-300 transition" do %>
    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
    Back to <%= @server.name %>
  <% end %>

  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6">
    <h1 class="text-lg font-semibold text-white mb-1">Backup Destination</h1>
    <p class="text-sm text-gray-500 mb-6">Configure S3-compatible storage for database backups. Supports AWS S3, Cloudflare R2, MinIO, Backblaze B2, DigitalOcean Spaces, and Wasabi.</p>

    <%= form_with model: @destination, url: dashboard_server_backup_destination_path(@server), method: :patch, class: "space-y-4" do |f| %>

      <div>
        <%= f.label :provider, "Provider", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
        <%= f.select :provider, BackupDestination::PROVIDERS.map { |k, v| [v[:name], k] }, {}, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white text-sm focus:ring-green-500 focus:border-green-500" %>
      </div>

      <div>
        <%= f.label :endpoint_url, "Endpoint URL (leave blank for AWS S3)", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
        <%= f.text_field :endpoint_url, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500", placeholder: "https://account-id.r2.cloudflarestorage.com" %>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <%= f.label :bucket, class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
          <%= f.text_field :bucket, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500", placeholder: "my-backups" %>
        </div>
        <div>
          <%= f.label :region, class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
          <%= f.text_field :region, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500", placeholder: "us-east-1" %>
        </div>
      </div>

      <div>
        <%= f.label :access_key_id, "Access Key ID", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
        <%= f.text_field :access_key_id, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500" %>
      </div>

      <div>
        <%= f.label :secret_access_key, "Secret Access Key", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
        <%= f.password_field :secret_access_key, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500", placeholder: @destination.persisted? ? "••••••••" : "" %>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <%= f.label :path_prefix, "Path Prefix", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
          <%= f.text_field :path_prefix, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500", placeholder: "wokku-backups" %>
        </div>
        <div>
          <%= f.label :retention_days, "Keep Backups (days)", class: "block text-xs text-gray-400 uppercase tracking-wider mb-1" %>
          <%= f.number_field :retention_days, class: "w-full rounded-md bg-[#0B1120] border-[#334155] text-white text-sm focus:ring-green-500 focus:border-green-500", min: 1, max: 365 %>
        </div>
      </div>

      <div class="flex items-center space-x-2">
        <%= f.check_box :enabled, class: "rounded bg-[#0B1120] border-[#334155] text-green-500 focus:ring-green-500" %>
        <%= f.label :enabled, "Enable automatic daily backups", class: "text-sm text-gray-400" %>
      </div>

      <div class="flex items-center space-x-3 pt-2">
        <%= f.submit "Save Backup Settings", class: "px-4 py-2 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition cursor-pointer" %>
        <%= link_to "Cancel", dashboard_server_path(@server), class: "text-sm text-gray-500 hover:text-gray-400 transition" %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside `resources :servers do` in the dashboard namespace, add:

```ruby
resource :backup_destination, only: [:edit, :update], controller: "backup_destinations"
```

- [ ] **Step 4: Add link to server show page**

Read `app/views/dashboard/servers/show.html.erb`. Add a "Backup Settings" button near the Terminal button:

```erb
<%= link_to edit_dashboard_server_backup_destination_path(@server), class: "inline-flex items-center px-3 py-1.5 bg-[#1E293B] border border-[#334155] text-gray-300 text-sm font-medium rounded-md hover:bg-[#334155] hover:text-white transition" do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/></svg>
  Backups
<% end %>
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/backup_destinations_controller.rb app/views/dashboard/backup_destinations/ config/routes.rb app/views/dashboard/servers/show.html.erb
git commit -m "feat: add S3 backup destination configuration UI"
```

---

## Task 7: Backup Browser and Actions (per database)

**Files:**
- Create: `app/controllers/dashboard/backups_controller.rb`
- Create: `app/views/dashboard/backups/index.html.erb`
- Modify: `app/views/dashboard/databases/show.html.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the controller**

```ruby
# app/controllers/dashboard/backups_controller.rb
module Dashboard
  class BackupsController < BaseController
    def index
      @database = DatabaseService.find(params[:database_id])
      authorize @database, :show?
      @backups = @database.backups.order(created_at: :desc).limit(30)
      @destination = @database.server.backup_destination
    end

    def create
      @database = DatabaseService.find(params[:database_id])
      authorize @database, :update?

      BackupJob.perform_later(@database.id)
      redirect_to dashboard_database_backups_path(@database), notice: "Backup started..."
    end

    def download
      backup = Backup.find(params[:id])
      authorize backup.database_service, :show?

      redirect_to backup.download_url(expires_in: 300), allow_other_host: true
    end

    def restore
      backup = Backup.find(params[:id])
      authorize backup.database_service, :update?

      begin
        RestoreService.new(backup).perform!
        redirect_to dashboard_database_backups_path(backup.database_service), notice: "Restore completed"
      rescue => e
        redirect_to dashboard_database_backups_path(backup.database_service), alert: "Restore failed: #{e.message}"
      end
    end
  end
end
```

- [ ] **Step 2: Write the backup list view**

```erb
<%# app/views/dashboard/backups/index.html.erb %>
<% content_for(:title, "Backups — #{@database.name}") %>

<div class="space-y-6">
  <div class="flex items-center justify-between">
    <div class="flex items-center space-x-3">
      <%= link_to dashboard_database_path(@database), class: "text-sm text-gray-500 hover:text-gray-300 transition" do %>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
      <% end %>
      <h1 class="text-lg font-semibold text-white">Backups</h1>
      <span class="text-sm text-gray-400 font-mono"><%= @database.name %> (<%= @database.service_type %>)</span>
    </div>
    <% if @destination&.enabled? %>
      <%= button_to "Backup Now", dashboard_database_backups_path(@database), method: :post, class: "inline-flex items-center px-3 py-1.5 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition cursor-pointer" %>
    <% else %>
      <span class="text-xs text-gray-600">No backup destination configured. <%= link_to "Configure", edit_dashboard_server_backup_destination_path(@database.server), class: "text-green-400 hover:text-green-300" %></span>
    <% end %>
  </div>

  <% if @backups.any? %>
    <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-xs text-gray-500 uppercase tracking-wider border-b border-[#334155]/30">
            <th class="px-5 py-2 text-left">Date</th>
            <th class="px-5 py-2 text-left">Status</th>
            <th class="px-5 py-2 text-right">Size</th>
            <th class="px-5 py-2 text-right">Duration</th>
            <th class="px-5 py-2 text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <% @backups.each do |backup| %>
            <tr class="border-b border-[#334155]/20">
              <td class="px-5 py-3 text-gray-300"><%= backup.created_at.strftime("%b %d, %Y %H:%M") %></td>
              <td class="px-5 py-3">
                <% case backup.status %>
                <% when "completed" %>
                  <span class="inline-flex px-2 py-0.5 rounded text-xs font-medium bg-green-500/10 text-green-400">Completed</span>
                <% when "running" %>
                  <span class="inline-flex px-2 py-0.5 rounded text-xs font-medium bg-yellow-500/10 text-yellow-400">Running</span>
                <% when "failed" %>
                  <span class="inline-flex px-2 py-0.5 rounded text-xs font-medium bg-red-500/10 text-red-400" title="<%= backup.error_message %>">Failed</span>
                <% when "pending" %>
                  <span class="inline-flex px-2 py-0.5 rounded text-xs font-medium bg-gray-500/10 text-gray-400">Pending</span>
                <% end %>
              </td>
              <td class="px-5 py-3 text-right text-gray-400 font-mono"><%= backup.size_human %></td>
              <td class="px-5 py-3 text-right text-gray-500"><%= backup.duration ? "#{backup.duration.round(1)}s" : "—" %></td>
              <td class="px-5 py-3 text-right">
                <% if backup.status == "completed" %>
                  <div class="flex items-center justify-end space-x-3">
                    <%= link_to "Download", download_dashboard_database_backup_path(@database, backup), class: "text-xs text-gray-400 hover:text-white transition" %>
                    <%= button_to "Restore", restore_dashboard_database_backup_path(@database, backup), method: :post, class: "text-xs text-yellow-400 hover:text-yellow-300 transition", data: { turbo_confirm: "Restore #{@database.name} from this backup? Current data will be overwritten." } %>
                  </div>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="text-center py-16 bg-[#1E293B]/40 rounded-lg border border-[#334155]/30">
      <p class="text-gray-500">No backups yet.</p>
      <% if @destination&.enabled? %>
        <p class="text-xs text-gray-600 mt-1">Automatic backups run daily at 2am UTC.</p>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside `resources :databases do` in the dashboard namespace:

```ruby
      resources :backups, only: [:index, :create], controller: "backups" do
        member do
          get :download
          post :restore
        end
      end
```

- [ ] **Step 4: Add backups link to database show page**

Read `app/views/dashboard/databases/show.html.erb`. Add a "Backups" button near the Delete button in the header:

```erb
<%= link_to dashboard_database_backups_path(@database), class: "inline-flex items-center px-3 py-1.5 bg-[#1E293B] border border-[#334155] text-gray-300 text-sm font-medium rounded-md hover:bg-[#334155] hover:text-white transition" do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/></svg>
  Backups
<% end %>
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/backups_controller.rb app/views/dashboard/backups/ app/views/dashboard/databases/show.html.erb config/routes.rb
git commit -m "feat: add backup browser with download and restore actions"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | aws-sdk-s3 + migrations | 2 | 1 |
| 2 | Models (Backup, BackupDestination) | 3 | 2 |
| 3 | BackupService (dump + upload) | 2 | 0 |
| 4 | RestoreService | 1 | 0 |
| 5 | Jobs (backup, scheduler, retention) | 3 | 1 |
| 6 | Backup destination config UI | 2 | 2 |
| 7 | Backup browser + actions | 2 | 2 |

**Total: 15 new files, 8 modified files, 7 tasks**

## Supported S3 Providers

| Provider | Endpoint URL | Notes |
|---|---|---|
| AWS S3 | (leave blank) | Default provider |
| Cloudflare R2 | `https://<account>.r2.cloudflarestorage.com` | No egress fees |
| MinIO | `http://your-minio:9000` | Self-hosted |
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` | Cheapest storage |
| DO Spaces | `https://<region>.digitaloceanspaces.com` | |
| Wasabi | `https://s3.<region>.wasabisys.com` | No egress fees |
