# 1-Click App Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a community-driven 1-click app template marketplace with 50 starter templates that users can deploy from the dashboard with a single click.

**Architecture:** Templates are static JSON files stored in `app/templates/` — anyone can add one via PR. A `TemplateRegistry` service loads and indexes them at boot. The dashboard shows a searchable gallery grid. When a user clicks "Deploy", a `TemplateDeployJob` background job clones the repo to the Dokku server, provisions addons, sets env vars, and triggers a build.

**Tech Stack:** Rails 8.1, Solid Queue, Tailwind CSS, Stimulus (search filter), Dokku SSH integration

---

## File Structure

### New Files

```
app/services/template_registry.rb         — Loads and indexes template JSON files
app/services/template_deployer.rb         — Deploys a template to Dokku (clone, addons, env, build)
app/jobs/template_deploy_job.rb           — Background job wrapper for TemplateDeployer
app/controllers/dashboard/templates_controller.rb  — Gallery index, show, create (deploy)
app/views/dashboard/templates/index.html.erb       — Gallery grid with search
app/views/dashboard/templates/_card.html.erb       — Template card partial
app/views/dashboard/templates/show.html.erb        — Template detail + deploy form
app/templates/registry.yml                — Master index of all templates
app/templates/<name>/template.json        — 50 individual template files
test/services/template_registry_test.rb
test/services/template_deployer_test.rb
test/controllers/dashboard/templates_controller_test.rb
```

### Modified Files

```
config/routes.rb                          — Add templates resource
app/views/dashboard/apps/index.html.erb   — Add "Browse Templates" button
app/views/dashboard/shared/_sidebar.html.erb — Add Templates nav item (optional)
```

---

## Task 1: Template Registry Service

**Files:**
- Create: `app/services/template_registry.rb`
- Create: `app/templates/registry.yml`
- Create: `app/templates/rails-tailwind/template.json` (first template for testing)
- Create: `test/services/template_registry_test.rb`

- [ ] **Step 1: Create the first template JSON for testing**

```json
// app/templates/rails-tailwind/template.json
{
  "name": "Rails + Tailwind",
  "slug": "rails-tailwind",
  "description": "Production-ready Rails 8 with Tailwind CSS and PostgreSQL",
  "category": "frameworks",
  "icon": "rails",
  "repo": "https://github.com/rails/rails-new",
  "branch": "main",
  "tags": ["ruby", "rails", "fullstack", "tailwind"],
  "addons": [
    { "type": "postgres", "tier": "mini" }
  ],
  "env": {
    "RAILS_ENV": "production",
    "RAILS_LOG_TO_STDOUT": "true"
  },
  "post_deploy": "bin/rails db:migrate"
}
```

- [ ] **Step 2: Create registry.yml**

```yaml
# app/templates/registry.yml
# Master index of all app templates.
# To add a template, create a directory under app/templates/ with a template.json file,
# then add an entry here. Community contributions welcome!

categories:
  - name: Frameworks
    slug: frameworks
  - name: Automation
    slug: automation
  - name: Communication
    slug: communication
  - name: Analytics
    slug: analytics
  - name: CMS & Content
    slug: cms
  - name: Productivity
    slug: productivity
  - name: E-Commerce
    slug: ecommerce
  - name: Developer Tools
    slug: devtools
  - name: AI
    slug: ai
  - name: Databases & Admin
    slug: databases
  - name: Media
    slug: media
  - name: Monitoring
    slug: monitoring
  - name: Security
    slug: security
  - name: File Storage
    slug: storage
  - name: Links & URL
    slug: links
  - name: Email
    slug: email
  - name: RSS & Reading
    slug: rss
  - name: Platform
    slug: platform
```

- [ ] **Step 3: Write the failing test**

```ruby
# test/services/template_registry_test.rb
require "test_helper"

class TemplateRegistryTest < ActiveSupport::TestCase
  test "loads templates from JSON files" do
    registry = TemplateRegistry.new
    templates = registry.all
    assert templates.any?
    assert templates.first[:name].present?
  end

  test "finds template by slug" do
    registry = TemplateRegistry.new
    template = registry.find("rails-tailwind")
    assert_equal "Rails + Tailwind", template[:name]
    assert_equal "postgres", template[:addons].first["type"]
  end

  test "returns nil for unknown slug" do
    registry = TemplateRegistry.new
    assert_nil registry.find("nonexistent")
  end

  test "filters by category" do
    registry = TemplateRegistry.new
    frameworks = registry.by_category("frameworks")
    assert frameworks.all? { |t| t[:category] == "frameworks" }
  end

  test "searches by name and tags" do
    registry = TemplateRegistry.new
    results = registry.search("rails")
    assert results.any? { |t| t[:slug] == "rails-tailwind" }
  end

  test "returns categories" do
    registry = TemplateRegistry.new
    cats = registry.categories
    assert cats.any? { |c| c["slug"] == "frameworks" }
  end
end
```

- [ ] **Step 4: Write the service**

```ruby
# app/services/template_registry.rb
class TemplateRegistry
  TEMPLATES_PATH = Rails.root.join("app/templates")

  def initialize
    @templates = load_templates
    @registry = load_registry
  end

  def all
    @templates
  end

  def find(slug)
    @templates.find { |t| t[:slug] == slug }
  end

  def by_category(category)
    @templates.select { |t| t[:category] == category }
  end

  def search(query)
    q = query.to_s.downcase
    @templates.select do |t|
      t[:name].downcase.include?(q) ||
        t[:description].to_s.downcase.include?(q) ||
        t[:tags].any? { |tag| tag.downcase.include?(q) }
    end
  end

  def categories
    @registry["categories"] || []
  end

  private

  def load_templates
    Dir[TEMPLATES_PATH.join("*/template.json")].filter_map do |path|
      data = JSON.parse(File.read(path))
      data.symbolize_keys.merge(slug: File.basename(File.dirname(path)))
    rescue JSON::ParserError => e
      Rails.logger.warn("Failed to parse template: #{path} — #{e.message}")
      nil
    end.sort_by { |t| t[:name] }
  end

  def load_registry
    path = TEMPLATES_PATH.join("registry.yml")
    path.exist? ? YAML.load_file(path) : {}
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/services/template_registry_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/template_registry.rb app/templates/ test/services/template_registry_test.rb
git commit -m "feat: add TemplateRegistry service for 1-click app templates"
```

---

## Task 2: Template Deployer Service

**Files:**
- Create: `app/services/template_deployer.rb`
- Create: `app/jobs/template_deploy_job.rb`
- Create: `test/services/template_deployer_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/template_deployer_test.rb
require "test_helper"

class TemplateDeployerTest < ActiveSupport::TestCase
  test "builds deploy steps from template" do
    template = {
      slug: "rails-tailwind",
      name: "Rails + Tailwind",
      repo: "https://github.com/rails/rails-new",
      branch: "main",
      addons: [{ "type" => "postgres", "tier" => "mini" }],
      env: { "RAILS_ENV" => "production" },
      post_deploy: "bin/rails db:migrate"
    }

    deployer = TemplateDeployer.new(
      template: template,
      app_name: "my-test-app",
      server: servers(:one),
      user: users(:one)
    )

    steps = deployer.build_steps
    assert_equal :create_app, steps[0][:action]
    assert_equal :provision_addon, steps[1][:action]
    assert_equal :set_env, steps[2][:action]
    assert_equal :deploy, steps[3][:action]
    assert_equal :post_deploy, steps[4][:action]
  end
end
```

- [ ] **Step 2: Write the deployer service**

```ruby
# app/services/template_deployer.rb
class TemplateDeployer
  attr_reader :template, :app_name, :server, :user, :log

  def initialize(template:, app_name:, server:, user:)
    @template = template
    @app_name = app_name
    @server = server
    @user = user
    @log = []
  end

  def deploy!
    client = Dokku::Client.new(server)

    step("Creating app #{app_name}...") do
      Dokku::Apps.new(client).create(app_name)
      AppRecord.create!(
        name: app_name,
        server: server,
        team: server.team,
        creator: user,
        deploy_branch: template[:branch] || "main",
        git_repository_url: template[:repo],
        status: :deploying
      )
    end

    app = AppRecord.find_by!(name: app_name, server: server)

    # Provision addons
    (template[:addons] || []).each do |addon|
      step("Provisioning #{addon['type']}...") do
        db_name = "#{app_name}-#{addon['type']}"
        Dokku::Databases.new(client).create(addon["type"], db_name)
        Dokku::Databases.new(client).link(addon["type"], db_name, app_name)
        DatabaseService.create!(
          name: db_name,
          service_type: addon["type"],
          server: server,
          status: :running
        )
        AppDatabase.create!(
          app_record: app,
          database_service: DatabaseService.find_by!(name: db_name, server: server),
          alias_name: db_name
        )
      end
    end

    # Set environment variables
    if template[:env].present?
      step("Setting environment variables...") do
        Dokku::Config.new(client).set(app_name, template[:env])
        template[:env].each do |key, value|
          app.env_vars.find_or_create_by!(key: key) { |ev| ev.value = value }
        end
      end
    end

    # Clone and deploy via Dokku git:sync (requires Dokku >= 0.25)
    step("Cloning #{template[:repo]} and deploying...") do
      begin
        client.run(
          "git:sync --build #{app_name} #{template[:repo]} #{template[:branch] || 'main'}",
          timeout: 300
        )
      rescue Dokku::Client::CommandError => e
        # Fallback: git:from-image or manual clone if git:sync not available
        raise unless e.message.include?("is not a dokku command")
        client.run("git:from-url #{app_name} #{template[:repo]}", timeout: 300)
      end
    end

    # Post-deploy command
    if template[:post_deploy].present?
      step("Running post-deploy: #{template[:post_deploy]}") do
        client.run("run #{app_name} #{template[:post_deploy]}", timeout: 120)
      end
    end

    app.update!(status: :running)
    @log << { step: "Deploy complete!", at: Time.current }

    { success: true, app: app, log: @log }
  rescue => e
    @log << { step: "Error", message: e.message, at: Time.current }
    app = AppRecord.find_by(name: app_name, server: server)
    app&.update!(status: :crashed)
    { success: false, error: e.message, log: @log }
  end

  def build_steps
    steps = [{ action: :create_app, detail: app_name }]

    (template[:addons] || []).each do |addon|
      steps << { action: :provision_addon, detail: addon }
    end

    steps << { action: :set_env, detail: template[:env] } if template[:env].present?
    steps << { action: :deploy, detail: template[:repo] }
    steps << { action: :post_deploy, detail: template[:post_deploy] } if template[:post_deploy].present?

    steps
  end

  private

  def step(message)
    @log << { step: message, at: Time.current }
    yield
  rescue => e
    @log << { step: "Failed: #{message}", error: e.message, at: Time.current }
    raise
  end
end
```

- [ ] **Step 3: Write the background job**

```ruby
# app/jobs/template_deploy_job.rb
class TemplateDeployJob < ApplicationJob
  queue_as :deploys

  def perform(template_slug:, app_name:, server_id:, user_id:)
    registry = TemplateRegistry.new
    template = registry.find(template_slug)
    raise "Template not found: #{template_slug}" unless template

    server = Server.find(server_id)
    user = User.find(user_id)

    deployer = TemplateDeployer.new(
      template: template,
      app_name: app_name,
      server: server,
      user: user
    )

    result = deployer.deploy!

    if result[:success]
      Rails.logger.info("TemplateDeployJob: #{template_slug} deployed as #{app_name}")
    else
      Rails.logger.error("TemplateDeployJob: Failed to deploy #{template_slug}: #{result[:error]}")
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/template_deployer_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/template_deployer.rb app/jobs/template_deploy_job.rb test/services/template_deployer_test.rb
git commit -m "feat: add TemplateDeployer service and background job"
```

---

## Task 3: Templates Controller and Routes

**Files:**
- Create: `app/controllers/dashboard/templates_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the controller**

```ruby
# app/controllers/dashboard/templates_controller.rb
module Dashboard
  class TemplatesController < BaseController
    def index
      registry = TemplateRegistry.new
      @categories = registry.categories
      @templates = if params[:q].present?
        registry.search(params[:q])
      elsif params[:category].present?
        registry.by_category(params[:category])
      else
        registry.all
      end
      @servers = policy_scope(Server)
    end

    def show
      registry = TemplateRegistry.new
      @template = registry.find(params[:id])
      return redirect_to dashboard_templates_path, alert: "Template not found" unless @template
      @servers = policy_scope(Server)
    end

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

      TemplateDeployJob.perform_later(
        template_slug: template[:slug],
        app_name: app_name,
        server_id: server.id,
        user_id: current_user.id
      )

      redirect_to dashboard_apps_path, notice: "Deploying #{template[:name]} as '#{app_name}'... This may take a few minutes."
    end
  end
end
```

- [ ] **Step 2: Add routes**

Add to `config/routes.rb` inside the `namespace :dashboard` block, before `resources :apps`:

```ruby
resources :templates, only: [:index, :show, :create]
```

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dashboard/templates_controller.rb config/routes.rb
git commit -m "feat: add templates controller and routes"
```

---

## Task 4: Template Gallery View

**Files:**
- Create: `app/views/dashboard/templates/index.html.erb`
- Create: `app/views/dashboard/templates/_card.html.erb`

- [ ] **Step 1: Write the gallery index view**

```erb
<%# app/views/dashboard/templates/index.html.erb %>
<% content_for(:title, "App Templates - Wokku") %>

<div class="space-y-6">
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-xl font-semibold text-white">App Templates</h1>
      <p class="mt-0.5 text-sm text-gray-500">Deploy popular apps and frameworks with one click</p>
    </div>
    <%= link_to dashboard_apps_path, class: "text-sm text-gray-500 hover:text-gray-300 transition" do %>
      &larr; Back to Apps
    <% end %>
  </div>

  <%# Search %>
  <div class="flex items-center space-x-3">
    <%= form_with url: dashboard_templates_path, method: :get, class: "flex-1", data: { turbo_frame: "_top" } do |f| %>
      <div class="relative">
        <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
        <%= f.search_field :q, value: params[:q], placeholder: "Search templates...", class: "w-full pl-10 pr-4 py-2 rounded-md bg-[#1E293B] border border-[#334155] text-sm text-white placeholder-gray-500 focus:ring-green-500 focus:border-green-500", autofocus: params[:q].present? %>
      </div>
    <% end %>
  </div>

  <%# Category pills %>
  <div class="flex flex-wrap gap-2">
    <%= link_to "All", dashboard_templates_path, class: "px-3 py-1 rounded-full text-xs font-medium transition #{params[:category].blank? ? 'bg-green-500 text-[#0B1120]' : 'bg-[#1E293B] text-gray-400 hover:text-white'}" %>
    <% @categories.each do |cat| %>
      <%= link_to cat["name"], dashboard_templates_path(category: cat["slug"]), class: "px-3 py-1 rounded-full text-xs font-medium transition #{params[:category] == cat['slug'] ? 'bg-green-500 text-[#0B1120]' : 'bg-[#1E293B] text-gray-400 hover:text-white'}" %>
    <% end %>
  </div>

  <%# Template grid %>
  <% if @templates.any? %>
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
      <% @templates.each do |template| %>
        <%= render "dashboard/templates/card", template: template %>
      <% end %>
    </div>
  <% else %>
    <div class="text-center py-16 bg-[#1E293B]/40 rounded-lg border border-[#334155]/30">
      <p class="text-gray-500">No templates found<%= " for '#{params[:q]}'" if params[:q].present? %>.</p>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Write the card partial**

```erb
<%# app/views/dashboard/templates/_card.html.erb %>
<%= link_to dashboard_template_path(template[:slug]), class: "block bg-[#1E293B]/60 rounded-lg border border-[#334155]/50 p-4 hover:bg-[#1E293B] hover:border-[#334155] transition group" do %>
  <div class="flex items-start space-x-3">
    <div class="w-10 h-10 rounded-lg bg-[#0B1120] border border-[#334155] flex items-center justify-center flex-shrink-0">
      <span class="text-lg"><%= template_icon(template[:icon]) %></span>
    </div>
    <div class="flex-1 min-w-0">
      <h3 class="text-sm font-semibold text-white group-hover:text-green-400 transition truncate"><%= template[:name] %></h3>
      <p class="text-xs text-gray-500 mt-0.5 line-clamp-2"><%= template[:description] %></p>
    </div>
  </div>
  <div class="mt-3 flex flex-wrap gap-1.5">
    <% (template[:tags] || []).first(3).each do |tag| %>
      <span class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-[#0B1120] text-gray-500"><%= tag %></span>
    <% end %>
    <% if template[:addons]&.any? %>
      <% template[:addons].each do |addon| %>
        <span class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-green-500/10 text-green-400"><%= addon["type"] %></span>
      <% end %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 3: Add template_icon helper**

Add to `app/helpers/application_helper.rb`:

```ruby
def template_icon(icon_name)
  icons = {
    "rails" => "🛤️", "ruby" => "💎", "node" => "🟢", "python" => "🐍",
    "go" => "🔷", "java" => "☕", "php" => "🐘", "elixir" => "💧",
    "rust" => "🦀", "analytics" => "📊", "chat" => "💬", "cms" => "📝",
    "automation" => "🔄", "ai" => "🤖", "ecommerce" => "🛒", "monitor" => "📈",
    "security" => "🔒", "storage" => "📦", "mail" => "📧", "rss" => "📰",
    "media" => "🎬", "wiki" => "📖", "link" => "🔗", "db" => "🗄️",
    "calendar" => "📅", "form" => "📋", "git" => "🔀", "api" => "⚡",
    "docker" => "🐳", "search" => "🔍", "url" => "🔗", "whatsapp" => "📱",
    "platform" => "🏗️"
  }
  icons[icon_name.to_s] || "📦"
end
```

- [ ] **Step 4: Commit**

```bash
git add app/views/dashboard/templates/ app/helpers/application_helper.rb
git commit -m "feat: add template gallery view with search and category filter"
```

---

## Task 5: Template Detail and Deploy View

**Files:**
- Create: `app/views/dashboard/templates/show.html.erb`

- [ ] **Step 1: Write the show/deploy view**

```erb
<%# app/views/dashboard/templates/show.html.erb %>
<% content_for(:title, "#{@template[:name]} - Wokku") %>

<div class="max-w-2xl mx-auto space-y-6">
  <%= link_to dashboard_templates_path, class: "inline-flex items-center text-sm text-gray-500 hover:text-gray-300 transition" do %>
    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
    Back to Templates
  <% end %>

  <%# Template info %>
  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6">
    <div class="flex items-start space-x-4">
      <div class="w-14 h-14 rounded-xl bg-[#0B1120] border border-[#334155] flex items-center justify-center flex-shrink-0">
        <span class="text-2xl"><%= template_icon(@template[:icon]) %></span>
      </div>
      <div>
        <h1 class="text-xl font-bold text-white"><%= @template[:name] %></h1>
        <p class="text-sm text-gray-400 mt-1"><%= @template[:description] %></p>
        <div class="mt-3 flex flex-wrap gap-1.5">
          <% (@template[:tags] || []).each do |tag| %>
            <span class="px-2 py-0.5 rounded text-xs font-medium bg-[#0B1120] text-gray-400"><%= tag %></span>
          <% end %>
        </div>
      </div>
    </div>

    <% if @template[:addons]&.any? %>
      <div class="mt-4 pt-4 border-t border-[#334155]/50">
        <h3 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">Included Add-ons</h3>
        <div class="flex flex-wrap gap-2">
          <% @template[:addons].each do |addon| %>
            <span class="inline-flex items-center px-2.5 py-1 rounded-md text-xs font-medium bg-green-500/10 text-green-400 border border-green-500/20">
              <%= addon["type"].capitalize %> (<%= addon["tier"] || "mini" %>)
            </span>
          <% end %>
        </div>
      </div>
    <% end %>

    <div class="mt-4 pt-4 border-t border-[#334155]/50">
      <a href="<%= @template[:repo] %>" target="_blank" rel="noopener" class="inline-flex items-center text-xs text-gray-500 hover:text-gray-300 transition font-mono">
        <svg class="w-3.5 h-3.5 mr-1.5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
        <%= @template[:repo].sub("https://github.com/", "") %>
      </a>
    </div>
  </div>

  <%# Deploy form %>
  <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-6">
    <h2 class="text-sm font-semibold text-white uppercase tracking-wider mb-4">Deploy this template</h2>

    <%= form_with url: dashboard_templates_path, method: :post, class: "space-y-4" do |f| %>
      <%= f.hidden_field :template_slug, value: @template[:slug] %>

      <div>
        <label class="block text-xs text-gray-400 uppercase tracking-wider mb-1">App Name</label>
        <input type="text" name="app_name" required placeholder="my-app" class="w-full rounded-md bg-[#0B1120] border-[#334155] text-white font-mono text-sm focus:ring-green-500 focus:border-green-500" pattern="[a-z][a-z0-9\-]*" title="Lowercase letters, numbers, and hyphens">
        <p class="mt-1 text-xs text-gray-600">Lowercase letters, numbers, and hyphens only</p>
      </div>

      <div>
        <label class="block text-xs text-gray-400 uppercase tracking-wider mb-1">Server</label>
        <select name="server_id" required class="w-full rounded-md bg-[#0B1120] border-[#334155] text-white text-sm focus:ring-green-500 focus:border-green-500">
          <option value="">Select a server</option>
          <% @servers.each do |server| %>
            <option value="<%= server.id %>"><%= server.name %></option>
          <% end %>
        </select>
      </div>

      <div class="pt-2">
        <button type="submit" class="w-full py-2.5 px-4 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition cursor-pointer text-center">
          Deploy <%= @template[:name] %>
        </button>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/templates/show.html.erb
git commit -m "feat: add template detail page with deploy form"
```

---

## Task 6: Update Apps Index with Templates Link

**Files:**
- Modify: `app/views/dashboard/apps/index.html.erb`

- [ ] **Step 1: Add "Browse Templates" button next to "New App"**

In `app/views/dashboard/apps/index.html.erb`, find the header div with the "New App" button and add a "Browse Templates" link before it:

Replace:
```erb
    <button data-action="click->slide-panel#open" class="inline-flex items-center px-3 py-1.5 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition cursor-pointer">
      <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4"/></svg>
      New App
    </button>
```

With:
```erb
    <div class="flex items-center space-x-2">
      <%= link_to dashboard_templates_path, class: "inline-flex items-center px-3 py-1.5 bg-[#1E293B] border border-[#334155] text-gray-300 text-sm font-medium rounded-md hover:bg-[#334155] hover:text-white transition" do %>
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z"/></svg>
        Templates
      <% end %>
      <button data-action="click->slide-panel#open" class="inline-flex items-center px-3 py-1.5 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition cursor-pointer">
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4"/></svg>
        New App
      </button>
    </div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/apps/index.html.erb
git commit -m "feat: add Templates button to apps index"
```

---

## Task 7: Create All 50 Template JSON Files

**Files:**
- Create: 50 template JSON files in `app/templates/`

This is a bulk data task. Create each template directory with a `template.json` file. All templates follow the same format. Here are all 50:

- [ ] **Step 1: Create framework templates (11 files)**

Templates to create:
1. `app/templates/rails-tailwind/template.json` — (already created in Task 1)
2. `app/templates/rails-api/template.json`
3. `app/templates/whoosh-falcon/template.json`
4. `app/templates/nextjs/template.json`
5. `app/templates/laravel/template.json`
6. `app/templates/django/template.json`
7. `app/templates/express-prisma/template.json`
8. `app/templates/go-fiber/template.json`
9. `app/templates/phoenix/template.json`
10. `app/templates/spring-boot/template.json`
11. `app/templates/fastapi/template.json`

Each template.json follows this format:
```json
{
  "name": "Display Name",
  "description": "One-line description",
  "category": "frameworks",
  "icon": "icon-key",
  "repo": "https://github.com/org/repo",
  "branch": "main",
  "tags": ["tag1", "tag2"],
  "addons": [{ "type": "postgres", "tier": "mini" }],
  "env": { "KEY": "value" },
  "post_deploy": "command"
}
```

Key details for each:
- **rails-api**: repo `https://github.com/rails/rails-new`, icon `rails`, tags `[ruby, rails, api]`, addons postgres, env `RAILS_ENV=production`, post_deploy `bin/rails db:migrate`
- **whoosh-falcon**: repo `https://github.com/socketry/whoosh`, icon `ruby`, tags `[ruby, whoosh, falcon, async]`, addons postgres
- **nextjs**: repo `https://github.com/vercel/next.js`, branch `canary`, icon `node`, tags `[node, react, nextjs, frontend]`, no addons, env `NODE_ENV=production`
- **laravel**: repo `https://github.com/laravel/laravel`, icon `php`, tags `[php, laravel, fullstack]`, addons postgres + redis, post_deploy `php artisan migrate --force`
- **django**: repo `https://github.com/djangopackages/djangopackages`, icon `python`, tags `[python, django, fullstack]`, addons postgres, post_deploy `python manage.py migrate`
- **express-prisma**: repo `https://github.com/prisma/prisma-examples`, icon `node`, tags `[node, express, prisma, api]`, addons postgres
- **go-fiber**: repo `https://github.com/gofiber/boilerplate`, icon `go`, tags `[go, fiber, api]`, addons postgres
- **phoenix**: repo `https://github.com/phoenixframework/phoenix`, icon `elixir`, tags `[elixir, phoenix, fullstack]`, addons postgres, post_deploy `mix ecto.migrate`
- **spring-boot**: repo `https://github.com/spring-guides/gs-spring-boot`, icon `java`, tags `[java, spring, api]`, addons postgres
- **fastapi**: repo `https://github.com/tiangolo/full-stack-fastapi-template`, icon `python`, tags `[python, fastapi, api]`, addons postgres, post_deploy `alembic upgrade head`

- [ ] **Step 2: Create open source app templates (39 files)**

Templates organized by category:

**Automation (3):**
- `n8n`: repo `https://github.com/n8n-io/n8n`, icon `automation`, tags `[automation, workflow, node]`, addons postgres, env `N8N_PORT=5678 DB_TYPE=postgresdb`
- `langflow`: repo `https://github.com/langflow-ai/langflow`, icon `ai`, tags `[ai, llm, python, workflow]`, addons postgres
- `flowise`: repo `https://github.com/FlowiseAI/Flowise`, icon `ai`, tags `[ai, llm, chatbot, node]`, addons postgres

**Communication (3):**
- `waha`: repo `https://github.com/devlikeapro/waha`, icon `whatsapp`, tags `[whatsapp, api, messaging]`, no addons
- `chatwoot`: repo `https://github.com/chatwoot/chatwoot`, icon `chat`, tags `[chat, support, customer-service, ruby]`, addons postgres + redis
- `typebot`: repo `https://github.com/baptisteArno/typebot.io`, icon `chat`, tags `[chatbot, forms, node]`, addons postgres

**Analytics (3):**
- `plausible`: repo `https://github.com/plausible/analytics`, icon `analytics`, tags `[analytics, privacy, elixir]`, addons postgres
- `umami`: repo `https://github.com/umami-software/umami`, icon `analytics`, tags `[analytics, node, lightweight]`, addons postgres
- `metabase`: repo `https://github.com/metabase/metabase`, icon `analytics`, tags `[bi, dashboards, java]`, addons postgres

**CMS & Content (4):**
- `ghost`: repo `https://github.com/TryGhost/Ghost`, icon `cms`, tags `[blog, cms, node]`, addons mysql
- `strapi`: repo `https://github.com/strapi/strapi`, icon `cms`, tags `[headless-cms, api, node]`, addons postgres
- `directus`: repo `https://github.com/directus/directus`, icon `cms`, tags `[headless-cms, api, node]`, addons postgres
- `bookstack`: repo `https://github.com/BookStackApp/BookStack`, icon `wiki`, tags `[wiki, docs, php]`, addons mysql

**Productivity (4):**
- `focalboard`: repo `https://github.com/mattermost/focalboard`, icon `form`, tags `[project-management, kanban, go]`, addons postgres
- `calcom`: repo `https://github.com/calcom/cal.com`, icon `calendar`, tags `[scheduling, calendar, node]`, addons postgres
- `formbricks`: repo `https://github.com/formbricks/formbricks`, icon `form`, tags `[surveys, forms, node]`, addons postgres
- `documenso`: repo `https://github.com/documenso/documenso`, icon `form`, tags `[e-signature, documents, node]`, addons postgres

**E-Commerce (2):**
- `medusa`: repo `https://github.com/medusajs/medusa`, icon `ecommerce`, tags `[ecommerce, headless, node]`, addons postgres + redis
- `saleor`: repo `https://github.com/saleor/saleor`, icon `ecommerce`, tags `[ecommerce, graphql, python]`, addons postgres + redis

**Developer Tools (3):**
- `gitea`: repo `https://github.com/go-gitea/gitea`, icon `git`, tags `[git, code-hosting, go]`, addons postgres
- `uptime-kuma`: repo `https://github.com/louislam/uptime-kuma`, icon `monitor`, tags `[monitoring, uptime, node]`, no addons
- `hoppscotch`: repo `https://github.com/hoppscotch/hoppscotch`, icon `api`, tags `[api-testing, http, node]`, addons postgres

**Databases/Admin (3):**
- `nocodb`: repo `https://github.com/nocodb/nocodb`, icon `db`, tags `[no-code, spreadsheet, node]`, addons postgres
- `baserow`: repo `https://github.com/baserow/baserow`, icon `db`, tags `[no-code, database, python]`, addons postgres + redis
- `outline`: repo `https://github.com/outline/outline`, icon `wiki`, tags `[wiki, knowledge-base, node]`, addons postgres + redis

**Media (2):**
- `immich`: repo `https://github.com/immich-app/immich`, icon `media`, tags `[photos, backup, node]`, addons postgres + redis
- `audiobookshelf`: repo `https://github.com/advplyr/audiobookshelf`, icon `media`, tags `[audiobooks, podcasts, node]`, no addons

**Monitoring (2):**
- `gatus`: repo `https://github.com/TwiN/gatus`, icon `monitor`, tags `[health, monitoring, go]`, no addons
- `grafana`: repo `https://github.com/grafana/grafana`, icon `monitor`, tags `[metrics, dashboards, go]`, no addons

**Security (1):**
- `vaultwarden`: repo `https://github.com/dani-garcia/vaultwarden`, icon `security`, tags `[passwords, vault, rust]`, no addons

**File Storage (2):**
- `filebrowser`: repo `https://github.com/filebrowser/filebrowser`, icon `storage`, tags `[files, browser, go]`, no addons
- `minio`: repo `https://github.com/minio/minio`, icon `storage`, tags `[s3, object-storage, go]`, no addons

**Links/URL (2):**
- `shlink`: repo `https://github.com/shlinkio/shlink`, icon `link`, tags `[url-shortener, links, php]`, addons postgres
- `linkstack`: repo `https://github.com/LinkStackOrg/LinkStack`, icon `link`, tags `[link-in-bio, links, php]`, no addons

**Email (1):**
- `listmonk`: repo `https://github.com/knadh/listmonk`, icon `mail`, tags `[newsletter, email, go]`, addons postgres

**RSS (2):**
- `miniflux`: repo `https://github.com/miniflux/v2`, icon `rss`, tags `[rss, reader, go]`, addons postgres
- `wallabag`: repo `https://github.com/wallabag/wallabag`, icon `rss`, tags `[read-later, bookmarks, php]`, addons postgres

**Platform (1):**
- `supabase`: repo `https://github.com/supabase/supabase`, icon `platform`, tags `[baas, firebase-alt, postgres]`, addons postgres

- [ ] **Step 3: Commit**

```bash
git add app/templates/
git commit -m "feat: add 50 app templates for 1-click deploy"
```

---

## Summary

| Task | Component | Files |
|---|---|---|
| 1 | TemplateRegistry service | 4 new |
| 2 | TemplateDeployer service + job | 3 new |
| 3 | Templates controller + routes | 1 new, 1 modified |
| 4 | Gallery view (index + card) | 2 new, 1 modified |
| 5 | Detail + deploy view | 1 new |
| 6 | Apps index "Templates" button | 1 modified |
| 7 | All 50 template JSON files | 50 new |

**Total: 62 new files, 3 modified files, 7 tasks**
