# Critical Bug Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5 highest-priority bugs from the 2026-03-30 feature audit to close the gap with Coolify.

**Architecture:** Each task is a standalone fix targeting a specific broken feature. Tasks 1-2 are view/controller fixes. Task 3 adds a new dashboard page wired to existing EE models. Task 4 improves error UX. Task 5 wires billing data creation into existing deploy jobs.

**Tech Stack:** Rails 8.1, ERB views, Tailwind CSS, Dokku SSH commands, ActionCable, EE modules (DynoTier, DynoAllocation, ResourceUsage)

---

## File Map

| Task | Files Created | Files Modified |
|------|--------------|----------------|
| 1 — Resource Limits | — | `app/controllers/dashboard/metrics_controller.rb` (already fixed), verify `app/views/dashboard/metrics/show.html.erb` |
| 2 — Rollback | — | `app/controllers/api/v1/releases_controller.rb`, `app/controllers/dashboard/releases_controller.rb`, `app/views/dashboard/releases/index.html.erb` |
| 3 — Dyno Tier UI | `app/views/dashboard/scaling/_dyno_tiers.html.erb` | `app/controllers/dashboard/scaling_controller.rb`, `app/views/dashboard/scaling/show.html.erb`, `config/routes.rb` |
| 4 — Container Metrics | — | `app/controllers/dashboard/metrics_controller.rb`, `app/views/dashboard/metrics/show.html.erb` |
| 5 — Billing ResourceUsage | — | `app/jobs/deploy_job.rb`, `app/jobs/github_deploy_job.rb`, `ee/app/models/concerns/ee_app_record.rb` |

---

### Task 1: Fix Resource Limits Display (already partially done)

**Files:**
- Verify: `app/controllers/dashboard/metrics_controller.rb:42-58` (fetch_resources method)
- Verify: `app/views/dashboard/metrics/show.html.erb:152-156` (key names)

The controller parser was already fixed this session (split on last colon). The view was also updated to use `default_limit_memory` keys. The fix needs to be deployed to production to take effect.

- [ ] **Step 1: Verify the local fix produces correct keys**

Run:
```bash
bin/rails runner "
server = Server.first
client = Dokku::Client.new(server)
output = client.run('resource:report topupnusantara')
result = {}
output.each_line do |line|
  line = line.strip
  next if line.blank? || line.start_with?('=')
  last_colon = line.rindex(':')
  next unless last_colon
  key = line[0...last_colon].strip.parameterize(separator: '_')
  value = line[(last_colon + 1)..].strip
  result[key] = value if value.present?
end
puts result.inspect
"
```

Expected: `{"default_limit_cpu"=>"50", "default_limit_memory"=>"512", "default_reserve_memory"=>"256"}`

- [ ] **Step 2: Verify view keys match controller output**

Check that `app/views/dashboard/metrics/show.html.erb` line 153-155 uses:
```erb
mem_limit_cfg = @resources["default_limit_memory"] || @resources["resource_limits_memory"]
cpu_limit_cfg = @resources["default_limit_cpu"] || @resources["resource_limits_cpu"]
mem_reserve = @resources["default_reserve_memory"] || @resources["resource_reservation_memory"]
```

If these already match (they should from our earlier edit), this task is done locally. The fix takes effect on next deploy.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dashboard/metrics_controller.rb app/views/dashboard/metrics/show.html.erb
git commit -m "fix: resource limits display — parse Dokku v0.37 output keys correctly"
```

---

### Task 2: Fix Rollback (API + Dashboard)

**Files:**
- Modify: `app/controllers/api/v1/releases_controller.rb:18-27`
- Modify: `app/controllers/dashboard/releases_controller.rb` (add rollback action)
- Modify: `app/views/dashboard/releases/index.html.erb` (add rollback button)
- Modify: `config/routes.rb` (add dashboard rollback route)

- [ ] **Step 1: Fix the API rollback to actually trigger a deploy**

Replace the `rollback` method in `app/controllers/api/v1/releases_controller.rb` (lines 18-27):

```ruby
def rollback
  release = @app_record.releases.find(params[:id])
  authorize release

  new_release = @app_record.releases.create!(
    description: "Rollback to v#{release.version}"
  )
  deploy = @app_record.deploys.create!(release: new_release, status: :pending)
  DeployJob.perform_later(deploy.id)

  render json: new_release, status: :created
end
```

- [ ] **Step 2: Add dashboard rollback action**

Add a `rollback` action to `app/controllers/dashboard/releases_controller.rb` after the `deploy` method (before `private`):

```ruby
def rollback
  authorize @app, :update?

  target_release = @app.releases.find(params[:id])
  new_release = @app.releases.create!(description: "Rollback to v#{target_release.version}")
  deploy = @app.deploys.create!(release: new_release, status: :pending)
  DeployJob.perform_later(deploy.id)

  redirect_to dashboard_app_releases_path(@app), notice: "Rolling back to v#{target_release.version}..."
end
```

- [ ] **Step 3: Add the dashboard route**

In `config/routes.rb`, find the releases resource block (around line 87):

```ruby
resources :releases, only: [:index], controller: "releases" do
  collection do
    post :deploy
  end
end
```

Replace with:

```ruby
resources :releases, only: [:index], controller: "releases" do
  collection do
    post :deploy
  end
  member do
    post :rollback
  end
end
```

- [ ] **Step 4: Add rollback button to releases view**

In `app/views/dashboard/releases/index.html.erb`, find the line that shows the time ago (around line 152):

```erb
          <span class="text-xs text-gray-500"><%= time_ago_in_words(release.created_at) %> ago</span>
```

Replace with:

```erb
          <div class="flex items-center space-x-3">
            <% if release.deploy&.succeeded? %>
              <%= button_to "Rollback", rollback_dashboard_app_release_path(@app, release),
                    method: :post,
                    data: { turbo_confirm: "Rollback to v#{release.version}?" },
                    class: "text-xs text-gray-400 hover:text-yellow-400 border border-[#334155] px-2 py-1 rounded transition cursor-pointer" %>
            <% end %>
            <span class="text-xs text-gray-500"><%= time_ago_in_words(release.created_at) %> ago</span>
          </div>
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/releases_controller.rb app/controllers/dashboard/releases_controller.rb app/views/dashboard/releases/index.html.erb config/routes.rb
git commit -m "fix: rollback now triggers actual deploy instead of creating orphan release"
```

---

### Task 3: Dyno Tier Selection UI

**Files:**
- Create: `app/views/dashboard/scaling/_dyno_tiers.html.erb`
- Modify: `app/controllers/dashboard/scaling_controller.rb` (add `change_tier` action + load tiers)
- Modify: `app/views/dashboard/scaling/show.html.erb` (add tier section)
- Modify: `config/routes.rb` (add `change_tier` route)

- [ ] **Step 1: Update the scaling controller to load dyno tiers and handle tier changes**

Replace the entire `app/controllers/dashboard/scaling_controller.rb` with:

```ruby
module Dashboard
  class ScalingController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      sync_process_scales
      @process_scales = @app.process_scales.order(:process_type)
      @dyno_tiers = defined?(DynoTier) ? DynoTier.available.order(:memory_mb) : []
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.find_by(process_type: "web") : nil
    end

    def update
      authorize @app, :update?

      scaling = {}
      params[:scaling].each do |type, count|
        scaling[type] = count.to_i
      end

      client = Dokku::Client.new(@app.server)
      Dokku::Processes.new(client).scale(@app.name, scaling)

      scaling.each do |type, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: type)
        ps.update!(count: count)
      end

      redirect_to dashboard_app_scaling_path(@app), notice: "Scaling updated."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Scaling failed: #{e.message}"
    end

    def change_tier
      authorize @app, :update?

      tier = DynoTier.find(params[:dyno_tier_id])
      process_type = params[:process_type] || "web"

      allocation = @app.dyno_allocations.find_or_initialize_by(process_type: process_type)
      allocation.dyno_tier = tier
      allocation.count ||= 1
      allocation.save!

      ApplyDynoTierJob.perform_later(allocation.id)

      redirect_to dashboard_app_scaling_path(@app), notice: "Container size changed to #{tier.name} (#{tier.memory_mb}MB). Applying..."
    rescue => e
      redirect_to dashboard_app_scaling_path(@app), alert: "Failed to change tier: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def sync_process_scales
      client = Dokku::Client.new(@app.server)
      report = Dokku::Processes.new(client).list(@app.name)

      process_types = {}
      report.each do |key, value|
        if key.match?(/status_\w+_\d+/)
          type = key.split("_")[1]
          process_types[type] ||= 0
          process_types[type] += 1
        end
      end

      process_types.each do |type, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: type)
        ps.update!(count: count) if ps.new_record?
      end
    rescue => e
      Rails.logger.warn "Failed to sync process scales for #{@app.name}: #{e.message}"
    end
  end
end
```

- [ ] **Step 2: Add the `change_tier` route**

In `config/routes.rb`, find the scaling resource (around line 96):

```ruby
resource :scaling, only: [:show, :update], controller: "scaling"
```

Replace with:

```ruby
resource :scaling, only: [:show, :update], controller: "scaling" do
  post :change_tier
end
```

- [ ] **Step 3: Create the dyno tier partial**

Create `app/views/dashboard/scaling/_dyno_tiers.html.erb`:

```erb
<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden mb-6">
  <div class="px-6 py-4 border-b border-[#334155]/50">
    <h2 class="text-base font-semibold text-white">Container Size</h2>
    <p class="text-sm text-gray-500 mt-1">Choose the resource allocation for your containers</p>
  </div>

  <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4 p-6">
    <% @dyno_tiers.each do |tier| %>
      <% is_current = @current_allocation&.dyno_tier_id == tier.id %>
      <div class="relative rounded-lg border p-4 <%= is_current ? 'border-green-500 bg-green-500/5' : 'border-[#334155] bg-[#0B1120] hover:border-[#475569]' %> transition">
        <% if is_current %>
          <div class="absolute -top-2 right-3">
            <span class="text-[10px] font-semibold uppercase tracking-wider bg-green-500 text-[#0B1120] px-1.5 py-0.5 rounded">Current</span>
          </div>
        <% end %>

        <h3 class="text-sm font-bold text-white capitalize"><%= tier.name %></h3>
        <div class="mt-2 space-y-1">
          <p class="text-xs text-gray-400"><span class="text-white font-mono font-bold"><%= tier.memory_mb %></span> MB RAM</p>
          <p class="text-xs text-gray-400"><span class="text-white font-mono font-bold"><%= tier.cpu_shares %></span> CPU shares</p>
          <% if tier.sleeps %>
            <p class="text-xs text-yellow-500">Sleeps after idle</p>
          <% end %>
        </div>

        <div class="mt-3 border-t border-[#334155]/50 pt-3">
          <% if tier.free? %>
            <p class="text-sm font-bold text-white">Free</p>
          <% else %>
            <p class="text-sm font-bold text-white">$<%= "%.2f" % tier.monthly_price_dollars %><span class="text-xs text-gray-500 font-normal">/mo</span></p>
          <% end %>
        </div>

        <% unless is_current %>
          <%= button_to "Select",
                change_tier_dashboard_app_scaling_path(@app),
                params: { dyno_tier_id: tier.id, process_type: "web" },
                method: :post,
                data: { turbo_confirm: "Change container to #{tier.name} (#{tier.memory_mb}MB)?" },
                class: "mt-3 w-full text-center px-3 py-1.5 text-xs font-semibold rounded-md border border-[#334155] text-gray-300 hover:bg-[#334155] hover:text-white transition cursor-pointer" %>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Add the tier partial to the scaling view**

In `app/views/dashboard/scaling/show.html.erb`, add the tier section right after the tabs render (line 1) and before the Process Scaling card (line 3):

Find:
```erb
<%= render "dashboard/apps/tabs", app: @app %>

<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden">
```

Replace with:
```erb
<%= render "dashboard/apps/tabs", app: @app %>

<% if @dyno_tiers.any? %>
  <%= render "dashboard/scaling/dyno_tiers" %>
<% end %>

<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden">
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard/scaling_controller.rb app/views/dashboard/scaling/_dyno_tiers.html.erb app/views/dashboard/scaling/show.html.erb config/routes.rb
git commit -m "feat: add dyno tier selection UI on scaling page"
```

---

### Task 4: Improve Container Metrics Error Message

**Files:**
- Modify: `app/controllers/dashboard/metrics_controller.rb:62-93` (fetch_container_stats)
- Modify: `app/views/dashboard/metrics/show.html.erb:137-143` (error display)

- [ ] **Step 1: Capture the specific error type in the controller**

In `app/controllers/dashboard/metrics_controller.rb`, add an instance variable for error tracking. Replace the `fetch_container_stats` method (lines 62-93):

```ruby
def fetch_container_stats
  server = @app.server
  output = Net::SSH.start(
    server.host,
    "root",
    port: server.port,
    non_interactive: true,
    timeout: 10
  ) do |ssh|
    ssh.exec!("docker stats --no-stream --format '{{json .}}'")
  end

  stats = []
  output.to_s.each_line do |line|
    data = JSON.parse(line)
    container_name = data["Name"]
    next unless container_name.start_with?("#{@app.name}.")

    stats << {
      name: container_name,
      cpu_percent: data["CPUPerc"].to_f,
      mem_usage: data["MemUsage"],
      mem_percent: data["MemPerc"].to_f,
      net_io: data["NetIO"],
      block_io: data["BlockIO"],
      pids: data["PIDs"]
    }
  end
  stats
rescue Net::SSH::AuthenticationFailed
  @metrics_error = "Authentication failed. Root SSH access is required for container metrics. The server is configured with user '#{@app.server.ssh_user || 'dokku'}' — add a root SSH key to enable metrics."
  []
rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::ConnectionTimeout
  @metrics_error = "Could not connect to server #{@app.server.host}. Check that the server is online and SSH port #{@app.server.port} is accessible."
  []
rescue => e
  Rails.logger.warn "Failed to fetch container stats for #{@app.name}: #{e.message}"
  @metrics_error = "Failed to fetch metrics: #{e.message}"
  []
end
```

- [ ] **Step 2: Update the view to show specific error messages**

In `app/views/dashboard/metrics/show.html.erb`, find the empty stats block (around lines 137-143):

```erb
<% else %>
  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6 mb-6 text-center">
    <svg class="mx-auto h-10 w-10 text-gray-600 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/></svg>
    <p class="text-sm text-gray-400">Unable to fetch container metrics.</p>
    <p class="text-xs text-gray-500 mt-1">Ensure root SSH access is available on the server.</p>
  </div>
<% end %>
```

Replace with:

```erb
<% else %>
  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6 mb-6 text-center">
    <svg class="mx-auto h-10 w-10 text-gray-600 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/></svg>
    <p class="text-sm text-gray-400">Unable to fetch container metrics.</p>
    <% if @metrics_error %>
      <p class="text-xs text-yellow-500/80 mt-1"><%= @metrics_error %></p>
    <% else %>
      <p class="text-xs text-gray-500 mt-1">Ensure root SSH access is available on the server.</p>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dashboard/metrics_controller.rb app/views/dashboard/metrics/show.html.erb
git commit -m "fix: show specific error messages when container metrics fail"
```

---

### Task 5: Auto-Create ResourceUsage on Deploy

**Files:**
- Modify: `app/jobs/deploy_job.rb:23-25` (after successful deploy)
- Modify: `app/jobs/github_deploy_job.rb:26-28` (after successful deploy)
- Modify: `ee/app/models/concerns/ee_app_record.rb` (add helper method)

- [ ] **Step 1: Add a helper to EeAppRecord to track resource usage**

Replace `ee/app/models/concerns/ee_app_record.rb` with:

```ruby
module EeAppRecord
  extend ActiveSupport::Concern

  included do
    has_many :dyno_allocations, dependent: :destroy
  end

  def track_resource_usage!
    return unless defined?(ResourceUsage)

    allocation = dyno_allocations.includes(:dyno_tier).find_by(process_type: "web")
    tier_name = allocation&.dyno_tier&.name || "eco"
    price = allocation&.dyno_tier&.price_cents_per_hour || 0

    # Don't duplicate — check for active usage
    existing = ResourceUsage.find_by(
      resource_id_ref: "AppRecord:#{id}",
      stopped_at: nil
    )
    return if existing

    ResourceUsage.create!(
      user_id: created_by_id,
      resource_type: "container",
      resource_id_ref: "AppRecord:#{id}",
      tier_name: tier_name,
      price_cents_per_hour: price,
      started_at: Time.current,
      metadata: { name: name, server: server.name }.to_json
    )
  end

  def stop_resource_usage!
    return unless defined?(ResourceUsage)

    ResourceUsage.where(
      resource_id_ref: "AppRecord:#{id}",
      stopped_at: nil
    ).find_each { |ru| ru.stop! }
  end
end
```

- [ ] **Step 2: Call track_resource_usage! after successful deploy**

In `app/jobs/deploy_job.rb`, find the success block (around line 23):

```ruby
deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
app.update!(status: :running)
DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
```

Replace with:

```ruby
deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
app.update!(status: :running)
app.track_resource_usage! if app.respond_to?(:track_resource_usage!)
DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
```

- [ ] **Step 3: Same for GithubDeployJob**

In `app/jobs/github_deploy_job.rb`, find the success block (around line 26):

```ruby
deploy.update!(status: :succeeded, log: log, finished_at: Time.current, commit_sha: commit_sha)
app.update!(status: :running)
DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
```

Replace with:

```ruby
deploy.update!(status: :succeeded, log: log, finished_at: Time.current, commit_sha: commit_sha)
app.update!(status: :running)
app.track_resource_usage! if app.respond_to?(:track_resource_usage!)
DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
```

- [ ] **Step 4: Commit**

```bash
git add ee/app/models/concerns/ee_app_record.rb app/jobs/deploy_job.rb app/jobs/github_deploy_job.rb
git commit -m "feat: auto-create ResourceUsage records on successful deploy for billing"
```

---

## Execution Notes

- **Task 1** is already done locally — just needs a deploy to production
- **Tasks 2-5** are independent of each other and can be worked on in parallel
- All tasks modify CE files except Task 5 which also modifies `ee/app/models/concerns/ee_app_record.rb`
- No database migrations are needed — all required tables and columns already exist
- `DynoTier` and `DynoAllocation` are EE models but the scaling controller gracefully handles their absence with `defined?()` checks
