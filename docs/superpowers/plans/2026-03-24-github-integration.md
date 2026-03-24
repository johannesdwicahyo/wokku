# GitHub App Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect GitHub repositories to Wokku apps for automatic deploys on push — users install the Wokku GitHub App, browse their repos from the dashboard, connect a repo to an app, and get automatic deployments on every push.

**Architecture:** Users install a GitHub App on their account/org. Wokku stores the `installation_id` on the user. When connecting a repo to an app, Wokku uses the installation's access token to list repos/branches and stores the `github_repo_full_name` on the AppRecord. GitHub sends push webhooks to Wokku, which verifies the HMAC signature and triggers a deploy via `dokku git:sync --build`.

**Tech Stack:** GitHub App API, Octokit gem, ActionCable (for deploy streaming), HMAC-SHA256 webhook verification

---

## File Structure

### New Files

```
app/services/github_app.rb                            — GitHub App API client (JWT auth, installation tokens, repo listing)
app/controllers/github/callbacks_controller.rb         — Handle GitHub App installation callback
app/controllers/webhooks/github_controller.rb          — Receive and verify GitHub push webhooks
app/controllers/dashboard/github_controller.rb         — Repo browser, connect/disconnect repo
app/views/dashboard/github/repos.html.erb              — Repo browser page
app/jobs/github_deploy_job.rb                          — Deploy triggered by GitHub push webhook
db/migrate/TIMESTAMP_add_github_fields.rb              — Add github columns to users and app_records
test/services/github_app_test.rb
test/controllers/webhooks/github_controller_test.rb
```

### Modified Files

```
Gemfile                                                — Add octokit gem
app/models/user.rb                                     — Add github_installation_id
app/models/app_record.rb                               — Add github_repo_full_name
app/views/dashboard/releases/index.html.erb            — Replace GitHub placeholder with connect UI
config/routes.rb                                       — Add GitHub callback, webhook, and repo routes
```

---

## Task 1: Add Octokit Gem and Migration

**Files:**
- Modify: `Gemfile`
- Create: `db/migrate/20260324000001_add_github_fields.rb`

- [ ] **Step 1: Add octokit gem**

Add to `Gemfile` after the SSH section:

```ruby
# GitHub Integration
gem "octokit"
```

Run: `bundle install`

- [ ] **Step 2: Create migration**

```ruby
# db/migrate/20260324000001_add_github_fields.rb
class AddGithubFields < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :github_installation_id, :bigint
    add_column :users, :github_username, :string
    add_column :app_records, :github_repo_full_name, :string
    add_column :app_records, :github_webhook_secret, :string

    add_index :users, :github_installation_id
    add_index :app_records, :github_repo_full_name
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate/20260324000001_add_github_fields.rb
git commit -m "feat: add octokit gem and GitHub fields migration"
```

---

## Task 2: GitHubApp Service

**Files:**
- Create: `app/services/github_app.rb`
- Create: `test/services/github_app_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/github_app_test.rb
require "test_helper"

class GitHubAppTest < ActiveSupport::TestCase
  test "installation_url returns correct URL" do
    url = GitHubApp.installation_url
    assert_includes url, "github.com/apps/"
  end

  test "verify_webhook_signature returns true for valid signature" do
    secret = "test_secret"
    payload = '{"action":"push"}'
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    assert GitHubApp.verify_webhook_signature(payload, signature, secret)
  end

  test "verify_webhook_signature returns false for invalid signature" do
    refute GitHubApp.verify_webhook_signature("payload", "sha256=invalid", "secret")
  end
end
```

- [ ] **Step 2: Write the service**

```ruby
# app/services/github_app.rb
class GitHubApp
  APP_ID = ENV["GITHUB_APP_ID"]
  PRIVATE_KEY = ENV["GITHUB_APP_PRIVATE_KEY"]
  WEBHOOK_SECRET = ENV["GITHUB_WEBHOOK_SECRET"]
  APP_SLUG = ENV.fetch("GITHUB_APP_SLUG", "wokku")

  class << self
    def installation_url
      "https://github.com/apps/#{APP_SLUG}/installations/new"
    end

    def configured?
      APP_ID.present? && PRIVATE_KEY.present?
    end

    def verify_webhook_signature(payload, signature, secret = WEBHOOK_SECRET)
      return false unless signature.present? && secret.present?
      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end

  def initialize(installation_id)
    @installation_id = installation_id
  end

  def client
    @client ||= Octokit::Client.new(access_token: installation_token)
  end

  def repos(per_page: 30, page: 1)
    # With installation token, use the app installation repos endpoint via JWT client
    app_client = Octokit::Client.new(bearer_token: jwt)
    app_client.list_app_installation_repositories(@installation_id, per_page: per_page, page: page)
  end

  def branches(repo_full_name)
    client.branches(repo_full_name).map(&:name)
  rescue Octokit::NotFound
    []
  end

  def repo(repo_full_name)
    client.repository(repo_full_name)
  rescue Octokit::NotFound
    nil
  end

  private

  def installation_token
    app_client = Octokit::Client.new(bearer_token: jwt)
    token = app_client.create_app_installation_access_token(@installation_id)
    token.token
  end

  def jwt
    private_key = OpenSSL::PKey::RSA.new(PRIVATE_KEY.gsub("\\n", "\n"))
    payload = {
      iat: Time.current.to_i - 60,
      exp: Time.current.to_i + (10 * 60),
      iss: APP_ID
    }
    JWT.encode(payload, private_key, "RS256")
  end
end
```

- [ ] **Step 3: Add jwt gem to Gemfile**

```ruby
gem "jwt"
```

Run: `bundle install`

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/github_app_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/github_app.rb test/services/github_app_test.rb Gemfile Gemfile.lock
git commit -m "feat: add GitHubApp service for installation token auth and API access"
```

---

## Task 3: GitHub Installation Callback

**Files:**
- Create: `app/controllers/github/callbacks_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the callback controller**

```ruby
# app/controllers/github/callbacks_controller.rb
module Github
  class CallbacksController < ApplicationController
    before_action :authenticate_user!

    def create
      installation_id = params[:installation_id]
      setup_action = params[:setup_action] # "install" or "update"

      if installation_id.present?
        current_user.update!(
          github_installation_id: installation_id,
          github_username: fetch_github_username(installation_id)
        )
        redirect_to dashboard_apps_path, notice: "GitHub connected successfully!"
      else
        redirect_to dashboard_apps_path, alert: "GitHub connection failed."
      end
    end

    private

    def fetch_github_username(installation_id)
      return nil unless GitHubApp.configured?
      github = GitHubApp.new(installation_id)
      result = github.repos(per_page: 1)
      result&.repositories&.first&.owner&.login
    rescue => e
      Rails.logger.warn("GitHubApp: Failed to fetch username: #{e.message}")
      nil
    end
  end
end
```

- [ ] **Step 2: Add routes**

In `config/routes.rb`, add BEFORE the `namespace :dashboard` block:

```ruby
# GitHub App callback
get "/github/callback", to: "github/callbacks#create", as: :github_callback
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/github/callbacks_controller.rb config/routes.rb
git commit -m "feat: add GitHub App installation callback handler"
```

---

## Task 4: GitHub Webhook Receiver

**Files:**
- Create: `app/controllers/webhooks/github_controller.rb`
- Create: `app/jobs/github_deploy_job.rb`
- Create: `test/controllers/webhooks/github_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the webhook controller**

```ruby
# app/controllers/webhooks/github_controller.rb
module Webhooks
  class GithubController < ActionController::API
    before_action :verify_signature!

    def create
      event = request.headers["X-GitHub-Event"]

      case event
      when "push"
        handle_push(JSON.parse(@payload))
      when "ping"
        head :ok
      else
        head :ok
      end
    end

    private

    def handle_push(payload)
      ref = payload["ref"] # "refs/heads/main"
      branch = ref&.sub("refs/heads/", "")
      repo_full_name = payload.dig("repository", "full_name")
      commit_sha = payload.dig("head_commit", "id")
      commit_message = payload.dig("head_commit", "message")

      return head :ok unless repo_full_name && branch

      # Find all apps connected to this repo + branch
      apps = AppRecord.where(github_repo_full_name: repo_full_name, deploy_branch: branch)

      apps.find_each do |app|
        deploy = app.deploys.create!(
          status: :pending,
          commit_sha: commit_sha,
          description: "GitHub push: #{commit_message&.truncate(80)}"
        )
        release = app.releases.create!(
          version: (app.releases.maximum(:version) || 0) + 1,
          deploy: deploy,
          description: commit_message&.truncate(200)
        )

        GithubDeployJob.perform_later(
          app_id: app.id,
          deploy_id: deploy.id,
          repo_full_name: repo_full_name,
          branch: branch,
          commit_sha: commit_sha
        )
      end

      head :ok
    end

    def verify_signature!
      request.body.rewind
      @payload = request.body.read
      signature = request.headers["X-Hub-Signature-256"]

      unless GitHubApp.verify_webhook_signature(@payload, signature)
        head :unauthorized
      end
    end
  end
end
```

- [ ] **Step 2: Write the deploy job**

```ruby
# app/jobs/github_deploy_job.rb
class GithubDeployJob < ApplicationJob
  queue_as :deploys

  DEPLOY_TIMEOUT = 15.minutes

  def perform(app_id:, deploy_id:, repo_full_name:, branch:, commit_sha:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)
    server = app.server
    client = Dokku::Client.new(server)

    deploy.update!(status: :building, started_at: Time.current)
    app.update!(status: :deploying)
    log = ""

    DeployChannel.broadcast_to(deploy, { type: "log", data: "Deploying #{repo_full_name}@#{branch} (#{commit_sha[0..6]})...\n" })

    Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
      # Use git:sync to pull from GitHub
      repo_url = "https://github.com/#{repo_full_name}.git"

      client.run_streaming("git:sync --build #{app.name} #{repo_url} #{branch}") do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current, commit_sha: commit_sha)
    app.update!(status: :running)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })

  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: log.to_s + "\nDeploy timed out", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Dokku::Client::CommandError => e
    deploy.update!(status: :failed, log: log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
  end
end
```

- [ ] **Step 3: Write test**

```ruby
# test/controllers/webhooks/github_controller_test.rb
require "test_helper"

class Webhooks::GithubControllerTest < ActionDispatch::IntegrationTest
  test "rejects unsigned webhook" do
    post "/webhooks/github", params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "accepts ping event" do
    payload = '{"zen":"test"}'
    secret = "test_secret"
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

    ENV["GITHUB_WEBHOOK_SECRET"] = secret
    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-GitHub-Event" => "ping",
        "X-Hub-Signature-256" => signature
      }
    assert_response :ok
    ENV.delete("GITHUB_WEBHOOK_SECRET")
  end
end
```

- [ ] **Step 4: Add webhook route**

In `config/routes.rb`, add near the other webhook routes (or before dashboard namespace):

```ruby
post "/webhooks/github", to: "webhooks/github#create"
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/webhooks/github_controller.rb app/jobs/github_deploy_job.rb test/controllers/webhooks/github_controller_test.rb config/routes.rb
git commit -m "feat: add GitHub webhook receiver and auto-deploy job"
```

---

## Task 5: Repo Browser and Connect UI

**Files:**
- Create: `app/controllers/dashboard/github_controller.rb`
- Create: `app/views/dashboard/github/repos.html.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the GitHub dashboard controller**

```ruby
# app/controllers/dashboard/github_controller.rb
module Dashboard
  class GithubController < BaseController
    def repos
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      unless current_user.github_installation_id
        return redirect_to GitHubApp.installation_url
      end

      github = GitHubApp.new(current_user.github_installation_id)
      @repos = github.repos(per_page: 50)&.repositories || []
      @branches = {}

      if params[:repo].present?
        @selected_repo = params[:repo]
        @branches = github.branches(params[:repo])
      end
    rescue Octokit::Error => e
      redirect_to dashboard_app_releases_path(@app), alert: "GitHub error: #{e.message}"
    end

    def connect
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      repo = params[:repo]
      branch = params[:branch] || "main"

      @app.update!(
        github_repo_full_name: repo,
        git_repository_url: "https://github.com/#{repo}.git",
        deploy_branch: branch,
        github_webhook_secret: SecureRandom.hex(20)
      )

      redirect_to dashboard_app_releases_path(@app), notice: "Connected to #{repo} (#{branch})"
    end

    def disconnect
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :update?

      @app.update!(
        github_repo_full_name: nil,
        github_webhook_secret: nil
      )

      redirect_to dashboard_app_releases_path(@app), notice: "GitHub disconnected"
    end
  end
end
```

- [ ] **Step 2: Write the repo browser view**

```erb
<%# app/views/dashboard/github/repos.html.erb %>
<% content_for(:title, "Connect GitHub — #{@app.name}") %>

<div class="max-w-2xl mx-auto space-y-6">
  <%= link_to dashboard_app_releases_path(@app), class: "inline-flex items-center text-sm text-gray-500 hover:text-gray-300 transition" do %>
    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
    Back to Releases
  <% end %>

  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6">
    <h1 class="text-lg font-semibold text-white mb-1">Connect GitHub Repository</h1>
    <p class="text-sm text-gray-500 mb-6">Select a repository to auto-deploy to <span class="font-mono text-gray-400"><%= @app.name %></span></p>

    <% if @repos.any? %>
      <div class="space-y-2 max-h-96 overflow-y-auto">
        <% @repos.each do |repo| %>
          <% selected = @selected_repo == repo.full_name %>
          <%= link_to dashboard_app_github_repos_path(@app, repo: repo.full_name),
              class: "block p-3 rounded-lg border transition #{selected ? 'bg-green-500/10 border-green-500/30' : 'bg-[#0B1120] border-[#334155]/50 hover:border-[#475569]'}" do %>
            <div class="flex items-center justify-between">
              <div>
                <span class="text-sm font-medium text-white"><%= repo.full_name %></span>
                <% if repo.private %>
                  <span class="ml-1.5 px-1.5 py-0.5 rounded text-[10px] bg-yellow-500/10 text-yellow-400">private</span>
                <% end %>
              </div>
              <% if repo.language %>
                <span class="text-[10px] text-gray-500"><%= repo.language %></span>
              <% end %>
            </div>
            <% if repo.description %>
              <p class="text-xs text-gray-500 mt-1 truncate"><%= repo.description %></p>
            <% end %>
          <% end %>
        <% end %>
      </div>

      <% if @selected_repo && @branches.any? %>
        <div class="mt-6 pt-6 border-t border-[#334155]/50">
          <h3 class="text-sm font-medium text-white mb-3">Select branch for <span class="font-mono text-green-400"><%= @selected_repo %></span></h3>
          <div class="space-y-2">
            <% @branches.each do |branch| %>
              <%= link_to dashboard_app_github_connect_path(@app, repo: @selected_repo, branch: branch),
                  method: :post,
                  class: "block p-2.5 rounded-lg bg-[#0B1120] border border-[#334155]/50 hover:border-green-500/30 transition" do %>
                <div class="flex items-center justify-between">
                  <span class="text-sm text-gray-300 font-mono"><%= branch %></span>
                  <span class="text-xs text-green-400">Deploy &rarr;</span>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="text-center py-8">
        <p class="text-gray-500 text-sm">No repositories found. Make sure the Wokku GitHub App has access to your repositories.</p>
        <a href="<%= GitHubApp.installation_url %>" class="mt-4 inline-flex items-center text-sm text-green-400 hover:text-green-300">
          Manage GitHub App permissions &rarr;
        </a>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside `resources :apps do` in the dashboard namespace:

```ruby
      scope module: :github, controller: :github do
        get "github/repos", action: :repos, as: :github_repos
        post "github/connect", action: :connect, as: :github_connect
        delete "github/disconnect", action: :disconnect, as: :github_disconnect
      end
```

Note: These generate paths like `dashboard_app_github_repos_path(@app)`.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/dashboard/github_controller.rb app/views/dashboard/github/repos.html.erb config/routes.rb
git commit -m "feat: add GitHub repo browser and connect/disconnect UI"
```

---

## Task 6: Update Releases Page with GitHub Connect Section

**Files:**
- Modify: `app/views/dashboard/releases/index.html.erb`

- [ ] **Step 1: Replace the GitHub placeholder**

Read the file. Find the "Coming Soon" GitHub placeholder section (around lines 37-45). Replace it with:

```erb
    <%# GitHub Integration %>
    <div class="bg-[#1E293B]/50 rounded-lg border border-[#334155]/40 p-4">
      <div class="flex items-center space-x-2 mb-2">
        <svg class="w-4 h-4 text-gray-400" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
        <h3 class="text-xs font-semibold text-gray-300 uppercase tracking-wider">GitHub</h3>
      </div>
      <% if @app.github_repo_full_name.present? %>
        <div class="flex items-center justify-between">
          <div>
            <span class="text-sm text-white font-mono"><%= @app.github_repo_full_name %></span>
            <span class="text-xs text-gray-500 ml-1">(<%= @app.deploy_branch %>)</span>
          </div>
          <%= button_to "Disconnect", dashboard_app_github_disconnect_path(@app), method: :delete, class: "text-xs text-red-400 hover:text-red-300 transition", data: { turbo_confirm: "Disconnect GitHub?" } %>
        </div>
        <p class="text-xs text-gray-500 mt-1">Auto-deploys on push to <span class="font-mono"><%= @app.deploy_branch %></span></p>
      <% else %>
        <p class="text-xs text-gray-500 mb-3">Connect a GitHub repository for automatic deploys on push.</p>
        <% if GitHubApp.configured? %>
          <% if current_user.github_installation_id %>
            <%= link_to dashboard_app_github_repos_path(@app), class: "inline-flex items-center px-3 py-1.5 bg-[#0B1120] border border-[#334155] text-gray-300 text-xs font-medium rounded-md hover:bg-[#334155] hover:text-white transition" do %>
              Connect Repository
            <% end %>
          <% else %>
            <a href="<%= GitHubApp.installation_url %>" class="inline-flex items-center px-3 py-1.5 bg-[#0B1120] border border-[#334155] text-gray-300 text-xs font-medium rounded-md hover:bg-[#334155] hover:text-white transition">
              Install GitHub App
            </a>
          <% end %>
        <% else %>
          <span class="text-xs text-gray-600">GitHub App not configured. Set GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY.</span>
        <% end %>
      <% end %>
    </div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/releases/index.html.erb
git commit -m "feat: replace GitHub placeholder with connect/disconnect UI on releases page"
```

---

## Task 7: Update .env.example

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Add GitHub App env vars**

```
# GitHub App (optional — for auto-deploy from GitHub)
GITHUB_APP_ID=
GITHUB_APP_PRIVATE_KEY=
GITHUB_WEBHOOK_SECRET=
GITHUB_APP_SLUG=wokku
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: add GitHub App env vars to .env.example"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | Octokit gem + migration | 1 | 2 |
| 2 | GitHubApp service | 2 | 1 |
| 3 | Installation callback | 1 | 1 |
| 4 | Webhook receiver + deploy job | 3 | 1 |
| 5 | Repo browser + connect UI | 2 | 1 |
| 6 | Releases page update | 0 | 1 |
| 7 | Env vars documentation | 0 | 1 |

**Total: 9 new files, 8 modified files, 7 tasks**

## Setup Instructions

After deployment, the admin needs to:

1. Create a GitHub App at https://github.com/settings/apps/new with:
   - **Webhook URL:** `https://wokku.dev/webhooks/github`
   - **Webhook Secret:** (generate and save as `GITHUB_WEBHOOK_SECRET`)
   - **Callback URL:** `https://wokku.dev/github/callback`
   - **Permissions:** Repository contents (read), Metadata (read)
   - **Events:** Push

2. Set env vars:
   - `GITHUB_APP_ID` — from the app settings page
   - `GITHUB_APP_PRIVATE_KEY` — generate and download PEM
   - `GITHUB_WEBHOOK_SECRET` — the secret from step 1
   - `GITHUB_APP_SLUG` — the slug in the app URL (e.g., "wokku")
