# Real-Time Deploy Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream build/deploy output to the dashboard in real-time so users see exactly what's happening during app deployments (both template installs and manual deploys).

**Architecture:** Extend the existing `DeployChannel` + `DeployJob` streaming pattern to cover template deployments. `TemplateDeployJob` creates a `Deploy` record upfront, passes a broadcast callback to `TemplateDeployer`, and each step broadcasts progress. A new deploy show view renders streaming output via the existing `deploy_controller.js` Stimulus controller. The templates controller redirects to the deploy log page after triggering deployment.

**Tech Stack:** ActionCable (DeployChannel, already exists), Stimulus (deploy_controller.js, already exists), Solid Queue

---

## File Structure

### New Files

```
app/views/dashboard/deploys/show.html.erb        — Deploy log viewer with streaming output
app/controllers/dashboard/deploys_controller.rb   — Serves deploy log page
```

### Modified Files

```
app/services/template_deployer.rb                — Add broadcast callback for step progress
app/jobs/template_deploy_job.rb                   — Create Deploy record, broadcast via DeployChannel
app/controllers/dashboard/templates_controller.rb — Redirect to deploy log page after triggering deploy
app/views/dashboard/apps/show.html.erb            — Show deploying banner with link to logs
config/routes.rb                                  — Add deploys show route
app/javascript/controllers/deploy_controller.js   — Minor: handle "step" message type for template deploys
```

---

## Task 1: Deploy Log View and Controller

**Files:**
- Create: `app/controllers/dashboard/deploys_controller.rb`
- Create: `app/views/dashboard/deploys/show.html.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the controller**

```ruby
# app/controllers/dashboard/deploys_controller.rb
module Dashboard
  class DeploysController < BaseController
    def show
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :show?
      @deploy = @app.deploys.find(params[:id])
    end
  end
end
```

- [ ] **Step 2: Write the deploy log view**

```erb
<%# app/views/dashboard/deploys/show.html.erb %>
<% content_for(:title, "Deploy — #{@app.name}") %>

<div class="space-y-4">
  <div class="flex items-center justify-between">
    <div class="flex items-center space-x-3">
      <%= link_to dashboard_app_path(@app), class: "text-sm text-gray-500 hover:text-gray-300 transition" do %>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
      <% end %>
      <h1 class="text-lg font-semibold text-white font-mono"><%= @app.name %></h1>
      <span class="text-gray-600">&middot;</span>
      <span class="text-sm text-gray-400">Deploy #<%= @deploy.id %></span>
    </div>
    <div data-deploy-target="statusBadge">
      <% case @deploy.status %>
      <% when "pending" %>
        <span class="inline-flex items-center space-x-1.5 text-xs text-gray-400"><span class="w-1.5 h-1.5 rounded-full bg-gray-400 animate-pulse"></span><span>Pending</span></span>
      <% when "building" %>
        <span class="inline-flex items-center space-x-1.5 text-xs text-yellow-400"><span class="w-1.5 h-1.5 rounded-full bg-yellow-400 animate-pulse"></span><span>Building</span></span>
      <% when "succeeded" %>
        <span class="inline-flex items-center space-x-1.5 text-xs text-green-400"><span class="w-1.5 h-1.5 rounded-full bg-green-400"></span><span>Succeeded</span></span>
      <% when "failed" %>
        <span class="inline-flex items-center space-x-1.5 text-xs text-red-400"><span class="w-1.5 h-1.5 rounded-full bg-red-400"></span><span>Failed</span></span>
      <% when "timed_out" %>
        <span class="inline-flex items-center space-x-1.5 text-xs text-red-400"><span class="w-1.5 h-1.5 rounded-full bg-red-400"></span><span>Timed Out</span></span>
      <% end %>
    </div>
  </div>

  <div class="rounded-xl border border-[#1E293B] bg-[#0B1120] overflow-hidden"
       data-controller="deploy"
       data-deploy-deploy-id-value="<%= @deploy.id %>">
    <div class="flex items-center justify-between px-4 py-2.5 border-b border-[#1E293B]">
      <div class="flex items-center space-x-2">
        <div class="flex space-x-1.5">
          <div class="w-2.5 h-2.5 rounded-full bg-[#334155]"></div>
          <div class="w-2.5 h-2.5 rounded-full bg-[#334155]"></div>
          <div class="w-2.5 h-2.5 rounded-full bg-[#334155]"></div>
        </div>
        <span class="text-[10px] text-gray-600 font-mono">deploy log</span>
      </div>
      <% if @deploy.finished_at && @deploy.started_at %>
        <span class="text-[10px] text-gray-600 font-mono">
          Duration: <%= (@deploy.finished_at - @deploy.started_at).round(1) %>s
        </span>
      <% end %>
    </div>
    <div data-deploy-target="output"
         class="p-4 font-mono text-xs text-gray-300 whitespace-pre-wrap overflow-y-auto h-[calc(100vh-250px)] leading-relaxed"><%= @deploy.log %></div>
  </div>
</div>
```

- [ ] **Step 3: Add route**

In `config/routes.rb`, inside the `resources :apps do` block in `namespace :dashboard`, add:

```ruby
resources :deploys, only: [:show], controller: "deploys"
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/dashboard/deploys_controller.rb app/views/dashboard/deploys/show.html.erb config/routes.rb
git commit -m "feat: add deploy log viewer page"
```

---

## Task 2: Update TemplateDeployer with Broadcast Callback

**Files:**
- Modify: `app/services/template_deployer.rb`

- [ ] **Step 1: Add broadcast callback to TemplateDeployer**

Read the file first. Update the `initialize` method to accept an `on_progress` callback, and update the `step` method to call it. The key changes:

In `initialize`, add `on_progress: nil` parameter and store it as `@on_progress`.

Update the `step` private method to broadcast:

```ruby
  def step(message)
    @log << { step: message, at: Time.current }
    @on_progress&.call(message)
    yield
  rescue => e
    @log << { step: "Failed: #{message}", error: e.message, at: Time.current }
    @on_progress&.call("FAILED: #{message} — #{e.message}")
    raise
  end
```

Also, at the end of `deploy!`, before returning success, broadcast completion:

```ruby
    @on_progress&.call("Deploy complete!")
```

The full change is adding `on_progress:` to initialize and updating the step method. Do NOT rewrite the entire file — make surgical edits.

- [ ] **Step 2: Commit**

```bash
git add app/services/template_deployer.rb
git commit -m "feat: add broadcast callback to TemplateDeployer for real-time progress"
```

---

## Task 3: Update TemplateDeployJob to Create Deploy Records and Stream

**Files:**
- Modify: `app/jobs/template_deploy_job.rb`

- [ ] **Step 1: Rewrite the job to create a Deploy record and broadcast**

Read the existing file first. Replace the `perform` method with:

```ruby
# app/jobs/template_deploy_job.rb
class TemplateDeployJob < ApplicationJob
  queue_as :deploys

  def perform(template_slug:, app_name:, server_id:, user_id:, deploy_id: nil)
    registry = TemplateRegistry.new
    template = registry.find(template_slug)
    raise "Template not found: #{template_slug}" unless template

    server = Server.find(server_id)
    user = User.find(user_id)

    # Find or create deploy record for tracking
    deploy = deploy_id ? Deploy.find(deploy_id) : nil

    if deploy
      deploy.update!(status: :building, started_at: Time.current)
      broadcast(deploy, "log", "Starting deployment of #{template[:name]}...\n")
    end

    deployer = TemplateDeployer.new(
      template: template,
      app_name: app_name,
      server: server,
      user: user,
      on_progress: ->(message) {
        if deploy
          broadcast(deploy, "log", "#{message}\n")
        end
      }
    )

    result = deployer.deploy!

    if result[:success]
      # Link deploy to the created app
      app = result[:app]
      if deploy
        deploy.update!(
          app_record: app,
          status: :succeeded,
          log: result[:log].map { |l| l[:step] }.join("\n"),
          finished_at: Time.current
        )
        broadcast(deploy, "status", "succeeded")
      end
      Rails.logger.info("TemplateDeployJob: #{template_slug} deployed as #{app_name}")
    else
      if deploy
        deploy.update!(
          status: :failed,
          log: result[:log].map { |l| "#{l[:step]}#{l[:error] ? " — #{l[:error]}" : ""}" }.join("\n"),
          finished_at: Time.current
        )
        broadcast(deploy, "log", "\nDeploy failed: #{result[:error]}\n")
        broadcast(deploy, "status", "failed")
      end
      Rails.logger.error("TemplateDeployJob: Failed to deploy #{template_slug}: #{result[:error]}")
    end
  end

  private

  def broadcast(deploy, type, data)
    DeployChannel.broadcast_to(deploy, { type: type, data: data })
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/jobs/template_deploy_job.rb
git commit -m "feat: TemplateDeployJob creates Deploy record and broadcasts progress"
```

---

## Task 4: Update Templates Controller to Create Deploy and Redirect

**Files:**
- Modify: `app/controllers/dashboard/templates_controller.rb`

- [ ] **Step 1: Update the create action**

Read the existing file. Update the `create` action to create a Deploy record and redirect to the deploy log page instead of the apps index.

Replace the existing create action body (after validation) with:

```ruby
    def create
      registry = TemplateRegistry.new
      template = registry.find(params[:template_slug])
      return redirect_to dashboard_templates_path, alert: "Template not found" unless template

      server = policy_scope(Server).find(params[:server_id])
      app_name = params[:app_name].to_s.parameterize

      if app_name.blank?
        return redirect_to dashboard_template_path(params[:template_slug]), alert: "App name is required"
      end

      if AppRecord.exists?(name: app_name, server: server)
        return redirect_to dashboard_template_path(params[:template_slug]), alert: "App name already taken on this server"
      end

      # Create a temporary app record and deploy for tracking
      app = AppRecord.create!(
        name: app_name,
        server: server,
        team: server.team,
        creator: current_user,
        deploy_branch: "main",
        status: :deploying
      )

      deploy = app.deploys.create!(
        status: :pending,
        description: "Template deploy: #{template[:name]}"
      )

      TemplateDeployJob.perform_later(
        template_slug: template[:slug],
        app_name: app_name,
        server_id: server.id,
        user_id: current_user.id,
        deploy_id: deploy.id
      )

      redirect_to dashboard_app_deploy_path(app, deploy), notice: "Deploying #{template[:name]}..."
    end
```

**Note:** This creates the AppRecord upfront (before the job runs) so we have something to attach the deploy to and redirect to. The TemplateDeployer's `deploy!` method will need to handle the case where the AppRecord already exists — update it instead of creating a new one.

- [ ] **Step 2: Update TemplateDeployer to handle pre-existing AppRecord**

In `app/services/template_deployer.rb`, update the app creation step in `deploy!`. Find the line that does `AppRecord.create!` and change it to `find_or_create_by!`:

```ruby
    step("Creating app #{app_name}...") do
      Dokku::Apps.new(client).create(app_name)
      AppRecord.find_or_initialize_by(name: app_name, server: server).tap do |a|
        a.assign_attributes(
          team: server.team,
          creator: user,
          deploy_branch: template[:branch] || "main",
          git_repository_url: template[:repo],
          status: :deploying
        )
        a.save!
      end
    end
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dashboard/templates_controller.rb app/services/template_deployer.rb
git commit -m "feat: template deploys create Deploy record and redirect to log page"
```

---

## Task 5: Update Deploy Stimulus Controller for Template Steps

**Files:**
- Modify: `app/javascript/controllers/deploy_controller.js`

- [ ] **Step 1: Update the deploy controller to handle the deploy log view**

Read the existing file. The current controller works with `deployIdValue` and connects to `DeployChannel`. It already handles "log" and "status" message types. The only change needed is to ensure it works when the output target contains pre-existing text (from `@deploy.log` rendered server-side) and that status updates refresh the badge.

Update the `connected` callback to NOT clear the output (remove the `this.outputTarget.textContent = ""` line if present), and ensure the "status" handler updates the page:

```javascript
connected: () => {
  // Don't clear - server-side already rendered existing log content
  this.scrollToBottom()
},
```

Also add a `scrollToBottom` method:

```javascript
scrollToBottom() {
  if (this.hasOutputTarget) {
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
  }
}
```

And update the "log" received handler to call `scrollToBottom()` after appending.

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/deploy_controller.js
git commit -m "feat: update deploy controller for streaming deploy log view"
```

---

## Task 6: Deploying Banner on App Show Page

**Files:**
- Modify: `app/views/dashboard/apps/show.html.erb`

- [ ] **Step 1: Add deploying banner**

Read the file. Find a suitable location near the top of the page (after the app name/header, before tabs). Add a deploying banner that shows when the app is in deploying state:

```erb
<% if @app.deploying? %>
  <% latest_deploy = @app.deploys.order(created_at: :desc).first %>
  <% if latest_deploy %>
    <div class="mb-4 bg-yellow-500/10 border border-yellow-500/20 rounded-lg p-3 flex items-center justify-between">
      <div class="flex items-center space-x-2">
        <span class="w-2 h-2 rounded-full bg-yellow-400 animate-pulse"></span>
        <span class="text-sm text-yellow-400">Deploying...</span>
      </div>
      <%= link_to "View logs", dashboard_app_deploy_path(@app, latest_deploy), class: "text-xs text-yellow-400 hover:text-yellow-300 font-medium transition" %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/apps/show.html.erb
git commit -m "feat: show deploying banner with link to deploy logs"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | Deploy log viewer | 2 | 1 |
| 2 | TemplateDeployer broadcast callback | 0 | 1 |
| 3 | TemplateDeployJob streaming | 0 | 1 |
| 4 | Templates controller redirect + deployer update | 0 | 2 |
| 5 | Deploy Stimulus controller update | 0 | 1 |
| 6 | Deploying banner on app show | 0 | 1 |

**Total: 2 new files, 7 modified files, 6 tasks**
