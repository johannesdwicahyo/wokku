# Wokku.dev Documentation System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docusaurus-like multi-page documentation system inside the Rails app at `/docs/*`, powered by markdown files with channel-switching tabs (Web UI / CLI / API / MCP / Mobile).

**Architecture:** Markdown files in `docs/content/` rendered by a `DocsController` with a dedicated `docs` layout. Navigation from `docs/sidebar.yml`. Custom `:::tabs` syntax preprocessed into tabbed HTML. Stimulus controller for tab switching with localStorage persistence.

**Tech Stack:** Rails 8.1, commonmarker (markdown), rouge (syntax highlighting), Stimulus.js, Tailwind CSS, YAML sidebar config.

**Spec:** `docs/superpowers/specs/2026-04-08-docs-system-design.md`

---

## File Structure Overview

### New Files

```
# Gems
Gemfile                                          # Add commonmarker, rouge

# Controller & helpers
app/controllers/docs_controller.rb               # Show action, markdown rendering, tab preprocessing
app/helpers/docs_helper.rb                        # TOC extraction, prev/next helpers

# Layout & views
app/views/layouts/docs.html.erb                   # 3-column docs layout (sidebar, content, TOC)
app/views/docs/show.html.erb                      # Content renderer
app/views/docs/_sidebar.html.erb                  # Sidebar partial
app/views/docs/_toc.html.erb                      # Table of contents partial

# Stimulus controllers
app/javascript/controllers/docs_tabs_controller.js    # Tab switching + localStorage
app/javascript/controllers/docs_sidebar_controller.js # Collapsible sidebar sections + mobile drawer
app/javascript/controllers/docs_toc_controller.js     # Active heading tracking via IntersectionObserver
app/javascript/controllers/docs_search_controller.js  # Client-side search

# Sidebar config
docs/sidebar.yml                                  # Navigation structure

# Markdown content (initial pages)
docs/content/getting-started/sign-up.md
docs/content/getting-started/first-deploy.md
docs/content/getting-started/connect-server.md
docs/content/apps/create.md
docs/content/mcp/setup.md

# Tests
test/controllers/docs_controller_test.rb
test/helpers/docs_helper_test.rb
```

### Modified Files

```
Gemfile                     # Add commonmarker, rouge
Gemfile.lock                # Updated by bundle install
config/routes.rb            # Replace /docs route with DocsController
config/importmap.rb         # No changes needed (auto-loaded from controllers/)
```

### Deleted Files

```
app/views/pages/docs.html.erb    # Replaced by new docs system
```

---

## Task 1: Add Gems and Basic DocsController with Test

**Files:**
- Modify: `Gemfile`
- Create: `app/controllers/docs_controller.rb`
- Create: `app/helpers/docs_helper.rb`
- Create: `docs/sidebar.yml`
- Create: `docs/content/getting-started/sign-up.md`
- Modify: `config/routes.rb`
- Create: `test/controllers/docs_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/controllers/docs_controller_test.rb`:

```ruby
require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /docs redirects to getting-started" do
    get "/docs"
    assert_response :success
  end

  test "GET /docs/getting-started/sign-up renders page" do
    get "/docs/getting-started/sign-up"
    assert_response :success
    assert_select "h1", /Sign Up/
  end

  test "GET /docs/nonexistent returns 404" do
    get "/docs/nonexistent"
    assert_response :not_found
  end

  test "sidebar navigation is present" do
    get "/docs/getting-started/sign-up"
    assert_select "[data-controller='docs-sidebar']"
    assert_select "nav a[href='/docs/getting-started/sign-up']"
  end

  test "table of contents is generated from headings" do
    get "/docs/getting-started/sign-up"
    assert_select "[data-controller='docs-toc']"
  end

  test "prev/next navigation is present" do
    get "/docs/getting-started/sign-up"
    assert_select ".docs-prev-next"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: FAIL — DocsController doesn't exist yet

- [ ] **Step 3: Add gems**

Add to `Gemfile` after the `# Profiling` section:

```ruby
# Documentation
gem "commonmarker"
gem "rouge"
```

Run: `bundle install`

- [ ] **Step 4: Create sidebar config**

Create `docs/sidebar.yml`:

```yaml
- title: Getting Started
  icon: rocket_launch
  items:
    - title: Sign Up
      path: getting-started/sign-up
    - title: Your First Deploy
      path: getting-started/first-deploy
    - title: Connect a Server
      path: getting-started/connect-server

- title: Apps
  icon: deployed_code
  items:
    - title: Create an App
      path: apps/create
    - title: Deploy
      path: apps/deploy
    - title: GitHub Auto-Deploy
      path: apps/github-autodeploy
    - title: Environment Variables
      path: apps/config
    - title: Logs
      path: apps/logs
    - title: Restart / Stop / Start
      path: apps/lifecycle

- title: Templates
  icon: dashboard_customize
  items:
    - title: Browse Templates
      path: templates/browse
    - title: Deploy a Template
      path: templates/deploy

- title: Domains & SSL
  icon: language
  items:
    - title: Custom Domains
      path: domains-ssl/custom-domains
    - title: SSL Certificates
      path: domains-ssl/ssl

- title: Databases
  icon: database
  items:
    - title: Supported Engines
      path: databases/engines
    - title: Create & Link
      path: databases/create-link
    - title: Backups
      path: databases/backups

- title: Scaling
  icon: speed
  items:
    - title: Process Types & Dynos
      path: scaling/dynos
    - title: Dyno Tiers
      path: scaling/tiers

- title: Monitoring
  icon: monitoring
  items:
    - title: Logs
      path: monitoring/logs
    - title: Metrics
      path: monitoring/metrics
    - title: Health Checks
      path: monitoring/health-checks
    - title: Notifications
      path: monitoring/notifications

- title: Teams
  icon: group
  items:
    - title: Members & Roles
      path: teams/members
    - title: Permissions
      path: teams/permissions

- title: CLI
  icon: terminal
  items:
    - title: Installation
      path: cli/install
    - title: Commands Reference
      path: cli/commands

- title: API
  icon: api
  items:
    - title: Authentication
      path: api/authentication
    - title: Endpoints Reference
      path: api/endpoints

- title: Claude Code (MCP)
  icon: smart_toy
  items:
    - title: Setup
      path: mcp/setup
    - title: Available Tools
      path: mcp/tools

- title: Mobile App
  icon: phone_iphone
  items:
    - title: Download
      path: mobile/download
    - title: Push Notifications
      path: mobile/notifications

- title: Billing
  icon: payments
  items:
    - title: Plans & Pricing
      path: billing/plans
    - title: Usage
      path: billing/usage

- title: Troubleshooting
  icon: help
  items:
    - title: Common Issues
      path: troubleshooting/common
    - title: FAQ
      path: troubleshooting/faq
```

- [ ] **Step 5: Create first markdown doc**

Create `docs/content/getting-started/sign-up.md`:

```markdown
# Sign Up

Get started with Wokku in under a minute.

## Create Your Account

:::tabs
::web-ui
Go to [wokku.dev](https://wokku.dev) and click **Sign Up**. You can register with:

- **Email & password** — fill in the form and verify your email
- **GitHub** — click "Sign in with GitHub" for one-click registration
- **Google** — click "Sign in with Google"

::cli
First install the CLI, then log in:

```bash
curl -sL https://wokku.dev/cli/install.sh | bash
wokku auth:login
```

This opens your browser for authentication.

::api
Get a session token by logging in:

```bash
curl -X POST https://wokku.dev/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your-password"}'
```

Then create an API token for ongoing use:

```bash
curl -X POST https://wokku.dev/api/v1/auth/tokens \
  -H "Authorization: Bearer <session-token>" \
  -d '{"name": "my-token"}'
```

::mcp
Before using MCP, you need an account and API token. Sign up at [wokku.dev](https://wokku.dev), then follow the [MCP Setup](/docs/mcp/setup) guide.

::mobile
Download the Wokku app from the App Store or Google Play. Tap **Sign Up** and register with email, GitHub, or Google.
:::

## Next Steps

Once signed up, you're ready to [deploy your first app](/docs/getting-started/first-deploy).
```

- [ ] **Step 6: Create DocsController**

Create `app/controllers/docs_controller.rb`:

```ruby
class DocsController < ApplicationController
  layout "docs"

  def show
    @path = params[:path] || "getting-started/sign-up"
    @sidebar = load_sidebar
    @content = render_doc(@path)
    @toc = extract_toc(@content)
    @prev_page, @next_page = find_prev_next(@path)
  end

  private

  def load_sidebar
    @_sidebar ||= YAML.load_file(Rails.root.join("docs/sidebar.yml"))
  end

  def render_doc(path)
    file = Rails.root.join("docs/content/#{path}.md")
    raise ActiveRecord::RecordNotFound unless file.exist?

    raw = file.read
    processed = preprocess_tabs(raw)
    html = render_markdown(processed)
    add_heading_anchors(html)
  end

  def render_markdown(text)
    html = Commonmarker.to_html(text, options: {
      parse: { smart: true },
      render: { unsafe: true }
    })
    highlight_code_blocks(html)
  end

  def highlight_code_blocks(html)
    formatter = Rouge::Formatters::HTML.new
    html.gsub(%r{<pre><code class="language-(\w+)">(.*?)</code></pre>}m) do
      lang = $1
      code = CGI.unescapeHTML($2)
      lexer = Rouge::Lexer.find(lang) || Rouge::Lexers::PlainText.new
      highlighted = formatter.format(lexer.lex(code))
      %(<div class="docs-code-block"><div class="docs-code-lang">#{lang}</div><pre><code>#{highlighted}</code></pre></div>)
    end
  end

  def preprocess_tabs(content)
    content.gsub(/:::tabs\n(.*?):::/m) do
      tabs_content = $1
      channels = tabs_content.scan(/::(\S+)\n(.*?)(?=::\S|\z)/m)

      tab_buttons = channels.map do |key, _|
        label = tab_label(key)
        %(<button type="button" class="docs-tab-btn" data-docs-tabs-target="tab" data-tab="#{key}" data-action="click->docs-tabs#switch">#{label}</button>)
      end.join("\n")

      tab_panels = channels.map do |key, body|
        rendered = render_markdown(body.strip)
        %(<div class="docs-tab-panel" data-tab="#{key}">#{rendered}</div>)
      end.join("\n")

      <<~HTML
        <div class="docs-tabs" data-controller="docs-tabs">
          <div class="docs-tab-bar">#{tab_buttons}</div>
          #{tab_panels}
        </div>
      HTML
    end
  end

  def tab_label(key)
    {
      "web-ui" => "Web UI",
      "cli" => "CLI",
      "api" => "API",
      "mcp" => "Claude Code",
      "mobile" => "Mobile"
    }.fetch(key, key.titleize)
  end

  def add_heading_anchors(html)
    html.gsub(/<(h[23])[^>]*>(.*?)<\/\1>/i) do
      tag = $1
      text = $2.gsub(/<[^>]+>/, "") # strip inner HTML
      id = text.downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-")
      %(<#{tag} id="#{id}"><a href="##{id}" class="docs-anchor">#</a>#{$2}</#{tag}>)
    end
  end

  def extract_toc(html)
    html.scan(/<(h[23]) id="([^"]+)"[^>]*>.*?>(.*?)<\/\1>/i).map do |tag, id, text|
      { level: tag == "h2" ? 2 : 3, id: id, text: text.gsub(/<[^>]+>/, "") }
    end
  end

  def find_prev_next(path)
    flat = load_sidebar.flat_map { |section| section["items"].map { |item| item["path"] } }
    idx = flat.index(path)
    return [nil, nil] unless idx

    prev_path = idx > 0 ? flat[idx - 1] : nil
    next_path = idx < flat.length - 1 ? flat[idx + 1] : nil

    prev_item = prev_path ? find_sidebar_item(prev_path) : nil
    next_item = next_path ? find_sidebar_item(next_path) : nil

    [prev_item, next_item]
  end

  def find_sidebar_item(path)
    load_sidebar.each do |section|
      section["items"].each do |item|
        return { "title" => item["title"], "path" => item["path"] } if item["path"] == path
      end
    end
    nil
  end
end
```

- [ ] **Step 7: Create DocsHelper**

Create `app/helpers/docs_helper.rb`:

```ruby
module DocsHelper
  def docs_active?(path)
    @path == path
  end

  def docs_section_active?(section)
    section["items"].any? { |item| item["path"] == @path }
  end

  def docs_page_title
    item = nil
    @sidebar.each do |section|
      section["items"].each do |i|
        item = i if i["path"] == @path
      end
    end
    item ? "#{item['title']} - Wokku Docs" : "Documentation - Wokku"
  end
end
```

- [ ] **Step 8: Update routes**

In `config/routes.rb`, replace:

```ruby
get "/docs", to: "pages#docs"
```

with:

```ruby
get "/docs", to: "docs#show", as: :docs
get "/docs/*path", to: "docs#show", as: :docs_page
```

Remove `def docs; end` from `app/controllers/pages_controller.rb`.

- [ ] **Step 9: Run tests**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: Tests fail because layout and views don't exist yet. That's OK — the controller logic is wired up. We'll add views in Task 2.

- [ ] **Step 10: Commit**

```bash
git add Gemfile Gemfile.lock app/controllers/docs_controller.rb app/helpers/docs_helper.rb docs/sidebar.yml docs/content/getting-started/sign-up.md config/routes.rb test/controllers/docs_controller_test.rb
git commit -m "$(cat <<'EOF'
feat: add DocsController with markdown rendering and tab preprocessing

- commonmarker + rouge gems for markdown and syntax highlighting
- DocsController renders .md files from docs/content/
- Custom :::tabs syntax for channel-switching (Web UI/CLI/API/MCP/Mobile)
- Sidebar navigation from docs/sidebar.yml
- TOC extraction from h2/h3 headings
- Prev/next page navigation
EOF
)"
```

---

## Task 2: Docs Layout and Views

**Files:**
- Create: `app/views/layouts/docs.html.erb`
- Create: `app/views/docs/show.html.erb`
- Create: `app/views/docs/_sidebar.html.erb`
- Create: `app/views/docs/_toc.html.erb`
- Delete: `app/views/pages/docs.html.erb`
- Modify: `app/controllers/pages_controller.rb` (remove `docs` method)

- [ ] **Step 1: Create the docs layout**

Create `app/views/layouts/docs.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= docs_page_title %></title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Wokku documentation — deploy and manage applications on your own servers.">
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Inter:wght@300;400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0" rel="stylesheet">

  <%= stylesheet_link_tag :app %>
  <%= javascript_importmap_tags %>
</head>
<body class="bg-surface text-on-surface font-body antialiased">

  <%# Header %>
  <header class="sticky top-0 z-50 border-b border-outline-variant/20 bg-surface/95 backdrop-blur-sm">
    <div class="max-w-[1400px] mx-auto flex items-center justify-between h-14 px-4">
      <div class="flex items-center gap-6">
        <a href="/" class="font-headline font-bold text-lg text-on-surface hover:text-primary transition">Wokku</a>
        <span class="text-outline-variant/40">|</span>
        <a href="/docs" class="text-sm font-medium text-on-surface-variant hover:text-primary transition">Docs</a>
      </div>

      <div class="flex items-center gap-4">
        <%# Search %>
        <div class="relative" data-controller="docs-search">
          <input type="text"
                 placeholder="Search docs..."
                 class="w-64 bg-surface-container-low border border-outline-variant/30 rounded-lg px-3 py-1.5 text-sm text-on-surface placeholder-outline focus:outline-none focus:border-primary/50 focus:ring-1 focus:ring-primary/30"
                 data-docs-search-target="input"
                 data-action="input->docs-search#search keydown->docs-search#navigate">
          <kbd class="absolute right-2 top-1/2 -translate-y-1/2 text-[10px] text-outline border border-outline-variant/30 rounded px-1.5 py-0.5 pointer-events-none">/</kbd>
          <div class="absolute top-full left-0 right-0 mt-1 bg-surface-container-low border border-outline-variant/30 rounded-lg shadow-xl overflow-hidden hidden" data-docs-search-target="results">
          </div>
        </div>

        <% if user_signed_in? %>
          <%= link_to "Dashboard", dashboard_root_path, class: "text-sm text-on-surface-variant hover:text-primary transition" %>
        <% else %>
          <%= link_to "Sign In", new_user_session_path, class: "text-sm text-on-surface-variant hover:text-primary transition" %>
        <% end %>
      </div>
    </div>
  </header>

  <%# Mobile sidebar toggle %>
  <button class="lg:hidden fixed bottom-4 right-4 z-40 bg-primary text-surface rounded-full w-12 h-12 flex items-center justify-center shadow-lg"
          data-action="click->docs-sidebar#toggleMobile">
    <span class="material-symbols-outlined text-[20px]">menu</span>
  </button>

  <div class="max-w-[1400px] mx-auto flex">
    <%# Sidebar %>
    <%= render "docs/sidebar" %>

    <%# Main content %>
    <main class="flex-1 min-w-0 px-8 py-8 lg:px-12 lg:py-10">
      <%= yield %>
    </main>

    <%# Table of Contents (right rail) %>
    <%= render "docs/toc" %>
  </div>

</body>
</html>
```

- [ ] **Step 2: Create sidebar partial**

Create `app/views/docs/_sidebar.html.erb`:

```erb
<aside class="hidden lg:block w-60 shrink-0 border-r border-outline-variant/20 sticky top-14 h-[calc(100vh-3.5rem)] overflow-y-auto py-6 px-4"
       data-controller="docs-sidebar">
  <nav class="space-y-1">
    <% @sidebar.each_with_index do |section, idx| %>
      <div class="mb-1">
        <button type="button"
                class="w-full flex items-center gap-2 px-2 py-1.5 text-xs font-bold uppercase tracking-wider rounded-md transition
                       <%= docs_section_active?(section) ? 'text-primary' : 'text-outline hover:text-on-surface-variant' %>"
                data-action="click->docs-sidebar#toggle"
                data-docs-sidebar-target="section"
                data-index="<%= idx %>">
          <span class="material-symbols-outlined text-[16px]"><%= section['icon'] %></span>
          <span class="flex-1 text-left"><%= section['title'] %></span>
          <span class="material-symbols-outlined text-[14px] transition-transform <%= docs_section_active?(section) ? 'rotate-90' : '' %>"
                data-docs-sidebar-target="arrow"
                data-index="<%= idx %>">chevron_right</span>
        </button>

        <div class="ml-6 mt-0.5 space-y-0.5 <%= docs_section_active?(section) ? '' : 'hidden' %>"
             data-docs-sidebar-target="items"
             data-index="<%= idx %>">
          <% section['items'].each do |item| %>
            <a href="/docs/<%= item['path'] %>"
               class="block px-2 py-1 text-sm rounded-md transition
                      <%= docs_active?(item['path']) ? 'text-primary bg-primary/10 font-medium border-l-2 border-primary -ml-px pl-[7px]' : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high/30' %>">
              <%= item['title'] %>
            </a>
          <% end %>
        </div>
      </div>
    <% end %>
  </nav>
</aside>

<%# Mobile sidebar drawer %>
<div class="lg:hidden fixed inset-0 z-50 hidden" data-docs-sidebar-target="mobileOverlay">
  <div class="absolute inset-0 bg-black/50" data-action="click->docs-sidebar#toggleMobile"></div>
  <aside class="absolute left-0 top-0 bottom-0 w-72 bg-surface border-r border-outline-variant/20 overflow-y-auto py-6 px-4">
    <div class="flex items-center justify-between mb-4 px-2">
      <span class="font-headline font-bold text-sm text-on-surface">Documentation</span>
      <button data-action="click->docs-sidebar#toggleMobile" class="text-outline hover:text-on-surface">
        <span class="material-symbols-outlined text-[20px]">close</span>
      </button>
    </div>
    <nav class="space-y-1">
      <% @sidebar.each_with_index do |section, idx| %>
        <div class="mb-1">
          <button type="button"
                  class="w-full flex items-center gap-2 px-2 py-1.5 text-xs font-bold uppercase tracking-wider rounded-md transition
                         <%= docs_section_active?(section) ? 'text-primary' : 'text-outline hover:text-on-surface-variant' %>"
                  data-action="click->docs-sidebar#toggle"
                  data-index="<%= idx %>">
            <span class="material-symbols-outlined text-[16px]"><%= section['icon'] %></span>
            <span class="flex-1 text-left"><%= section['title'] %></span>
            <span class="material-symbols-outlined text-[14px] transition-transform <%= docs_section_active?(section) ? 'rotate-90' : '' %>">chevron_right</span>
          </button>
          <div class="ml-6 mt-0.5 space-y-0.5 <%= docs_section_active?(section) ? '' : 'hidden' %>">
            <% section['items'].each do |item| %>
              <a href="/docs/<%= item['path'] %>"
                 class="block px-2 py-1 text-sm rounded-md transition
                        <%= docs_active?(item['path']) ? 'text-primary bg-primary/10 font-medium' : 'text-on-surface-variant hover:text-on-surface' %>">
                <%= item['title'] %>
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </nav>
  </aside>
</div>
```

- [ ] **Step 3: Create TOC partial**

Create `app/views/docs/_toc.html.erb`:

```erb
<% if @toc.present? %>
  <aside class="hidden xl:block w-48 shrink-0 sticky top-14 h-[calc(100vh-3.5rem)] overflow-y-auto py-8 pr-4"
         data-controller="docs-toc">
    <p class="text-[10px] text-outline uppercase tracking-widest font-bold mb-3 px-2">On This Page</p>
    <nav class="space-y-0.5">
      <% @toc.each do |heading| %>
        <a href="#<%= heading[:id] %>"
           class="block text-sm py-0.5 transition hover:text-primary
                  <%= heading[:level] == 2 ? 'px-2 text-on-surface-variant font-medium' : 'px-2 pl-5 text-outline' %>"
           data-docs-toc-target="link"
           data-heading-id="<%= heading[:id] %>">
          <%= heading[:text] %>
        </a>
      <% end %>
    </nav>
  </aside>
<% end %>
```

- [ ] **Step 4: Create show view**

Create `app/views/docs/show.html.erb`:

```erb
<% content_for(:title, docs_page_title) %>

<article class="docs-content max-w-3xl">
  <%= raw @content %>
</article>

<%# Prev / Next navigation %>
<nav class="docs-prev-next max-w-3xl mt-12 pt-6 border-t border-outline-variant/20 flex items-center justify-between">
  <% if @prev_page %>
    <a href="/docs/<%= @prev_page['path'] %>" class="group flex items-center gap-2 text-sm text-on-surface-variant hover:text-primary transition">
      <span class="material-symbols-outlined text-[16px] group-hover:-translate-x-0.5 transition-transform">arrow_back</span>
      <span><%= @prev_page['title'] %></span>
    </a>
  <% else %>
    <div></div>
  <% end %>

  <% if @next_page %>
    <a href="/docs/<%= @next_page['path'] %>" class="group flex items-center gap-2 text-sm text-on-surface-variant hover:text-primary transition">
      <span><%= @next_page['title'] %></span>
      <span class="material-symbols-outlined text-[16px] group-hover:translate-x-0.5 transition-transform">arrow_forward</span>
    </a>
  <% end %>
</nav>
```

- [ ] **Step 5: Delete old docs page and clean up PagesController**

Delete `app/views/pages/docs.html.erb`.

In `app/controllers/pages_controller.rb`, remove:

```ruby
def docs
end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: Tests pass (layout renders, content shows, sidebar present)

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts/docs.html.erb app/views/docs/ config/routes.rb app/controllers/pages_controller.rb
git rm app/views/pages/docs.html.erb
git commit -m "$(cat <<'EOF'
feat: add docs layout with sidebar, TOC, and prev/next navigation

- 3-column layout: collapsible sidebar, content, right-rail TOC
- Mobile responsive: sidebar becomes slide-out drawer
- Prev/next page navigation from sidebar order
- Remove old single-page docs
EOF
)"
```

---

## Task 3: Stimulus Controllers (Tabs, Sidebar, TOC)

**Files:**
- Create: `app/javascript/controllers/docs_tabs_controller.js`
- Create: `app/javascript/controllers/docs_sidebar_controller.js`
- Create: `app/javascript/controllers/docs_toc_controller.js`

- [ ] **Step 1: Create tabs controller**

Create `app/javascript/controllers/docs_tabs_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab"]

  connect() {
    this.panels = this.element.querySelectorAll(".docs-tab-panel")
    const saved = localStorage.getItem("wokku-docs-channel")
    const initial = saved && this.hasTab(saved) ? saved : this.firstTab()
    this.activate(initial)
  }

  switch(event) {
    const tab = event.currentTarget.dataset.tab
    this.activate(tab)
    localStorage.setItem("wokku-docs-channel", tab)

    // Sync all tab groups on the page
    document.querySelectorAll("[data-controller='docs-tabs']").forEach(group => {
      if (group !== this.element) {
        const ctrl = this.application.getControllerForElementAndIdentifier(group, "docs-tabs")
        if (ctrl && ctrl.hasTab(tab)) ctrl.activate(tab)
      }
    })
  }

  activate(tab) {
    this.tabTargets.forEach(btn => {
      const active = btn.dataset.tab === tab
      btn.classList.toggle("docs-tab-btn--active", active)
    })
    this.panels.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tab)
    })
  }

  hasTab(tab) {
    return this.tabTargets.some(btn => btn.dataset.tab === tab)
  }

  firstTab() {
    return this.tabTargets[0]?.dataset.tab || "web-ui"
  }
}
```

- [ ] **Step 2: Create sidebar controller**

Create `app/javascript/controllers/docs_sidebar_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["section", "items", "arrow", "mobileOverlay"]

  toggle(event) {
    const index = event.currentTarget.dataset.index
    const items = this.itemsTargets.filter(el => el.dataset.index === index)
    const arrows = this.arrowTargets.filter(el => el.dataset.index === index)

    items.forEach(el => el.classList.toggle("hidden"))
    arrows.forEach(el => el.classList.toggle("rotate-90"))
  }

  toggleMobile() {
    if (this.hasMobileOverlayTarget) {
      this.mobileOverlayTarget.classList.toggle("hidden")
      document.body.classList.toggle("overflow-hidden")
    }
  }
}
```

- [ ] **Step 3: Create TOC controller**

Create `app/javascript/controllers/docs_toc_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.observer = new IntersectionObserver(
      entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.setActive(entry.target.id)
          }
        })
      },
      { rootMargin: "-80px 0px -70% 0px" }
    )

    this.linkTargets.forEach(link => {
      const heading = document.getElementById(link.dataset.headingId)
      if (heading) this.observer.observe(heading)
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  setActive(id) {
    this.linkTargets.forEach(link => {
      const active = link.dataset.headingId === id
      link.classList.toggle("text-primary", active)
      link.classList.toggle("text-on-surface-variant", active && link.classList.contains("text-on-surface-variant"))
    })
  }
}
```

- [ ] **Step 4: Verify Stimulus auto-loading**

Check that `config/importmap.rb` has:

```ruby
pin_all_from "app/javascript/controllers", under: "controllers"
```

This is already present — new controllers are auto-discovered.

- [ ] **Step 5: Run tests and verify in browser**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: All tests pass

Run: `bin/dev` and visit `http://localhost:3000/docs`
Expected: Sidebar, content with tabs, TOC all render and work

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/docs_tabs_controller.js app/javascript/controllers/docs_sidebar_controller.js app/javascript/controllers/docs_toc_controller.js
git commit -m "$(cat <<'EOF'
feat: add Stimulus controllers for docs tabs, sidebar, and TOC

- docs_tabs: channel switching with localStorage persistence, syncs across page
- docs_sidebar: collapsible sections, mobile drawer toggle
- docs_toc: active heading tracking via IntersectionObserver
EOF
)"
```

---

## Task 4: Docs CSS Styles

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Add docs-specific styles**

Add to the end of `app/assets/tailwind/application.css`:

```css
/* === Documentation === */
.docs-content h1 {
  @apply font-headline text-3xl font-bold text-on-surface mb-6;
}
.docs-content h2 {
  @apply font-headline text-xl font-bold text-on-surface mt-10 mb-4;
}
.docs-content h3 {
  @apply font-headline text-base font-bold text-on-surface mt-6 mb-3;
}
.docs-content p {
  @apply text-sm text-on-surface-variant leading-relaxed mb-4;
}
.docs-content ul, .docs-content ol {
  @apply text-sm text-on-surface-variant mb-4 pl-5 space-y-1;
}
.docs-content ul { @apply list-disc; }
.docs-content ol { @apply list-decimal; }
.docs-content li { @apply leading-relaxed; }
.docs-content a {
  @apply text-primary hover:underline;
}
.docs-content strong {
  @apply text-on-surface font-medium;
}
.docs-content code {
  @apply bg-surface-container-high/50 text-primary px-1.5 py-0.5 rounded text-xs font-mono;
}
.docs-content pre code {
  @apply bg-transparent p-0 text-inherit;
}
.docs-content table {
  @apply w-full text-sm mb-6;
}
.docs-content thead {
  @apply bg-surface-container-high;
}
.docs-content th {
  @apply px-4 py-2 text-left text-[10px] text-outline uppercase tracking-wider font-bold;
}
.docs-content td {
  @apply px-4 py-2.5 text-on-surface-variant border-t border-outline-variant/10;
}
.docs-content hr {
  @apply border-outline-variant/20 my-8;
}
.docs-content blockquote {
  @apply border-l-2 border-primary/50 pl-4 py-1 my-4 text-sm text-on-surface-variant italic;
}

/* Code blocks */
.docs-code-block {
  @apply bg-surface-container-lowest rounded-lg mb-4 overflow-hidden border border-outline-variant/10;
}
.docs-code-block .docs-code-lang {
  @apply text-[10px] text-outline uppercase tracking-wider font-bold px-4 py-1.5 border-b border-outline-variant/10 bg-surface-container-low;
}
.docs-code-block pre {
  @apply p-4 overflow-x-auto text-xs leading-relaxed;
}
.docs-code-block code {
  @apply font-mono text-on-surface-variant;
}

/* Heading anchors */
.docs-anchor {
  @apply text-outline-variant/0 hover:text-outline ml-1 no-underline transition;
}
.docs-content h2:hover .docs-anchor,
.docs-content h3:hover .docs-anchor {
  @apply text-outline;
}

/* Channel tabs */
.docs-tabs {
  @apply mb-6 border border-outline-variant/15 rounded-lg overflow-hidden;
}
.docs-tab-bar {
  @apply flex gap-0 bg-surface-container-low border-b border-outline-variant/15;
}
.docs-tab-btn {
  @apply px-4 py-2 text-xs font-medium text-outline hover:text-on-surface-variant transition border-b-2 border-transparent;
}
.docs-tab-btn--active {
  @apply text-primary border-primary bg-surface-container-high/30;
}
.docs-tab-panel {
  @apply p-5;
}
.docs-tab-panel > :first-child {
  @apply mt-0;
}
.docs-tab-panel > :last-child {
  @apply mb-0;
}

/* Rouge syntax highlighting (dark theme) */
.docs-code-block .highlight .k, .docs-code-block .highlight .kd,
.docs-code-block .highlight .kn, .docs-code-block .highlight .kp,
.docs-code-block .highlight .kr, .docs-code-block .highlight .kt { color: #c0c1ff; }
.docs-code-block .highlight .s, .docs-code-block .highlight .s1,
.docs-code-block .highlight .s2, .docs-code-block .highlight .sb,
.docs-code-block .highlight .sc, .docs-code-block .highlight .sd,
.docs-code-block .highlight .se, .docs-code-block .highlight .sh,
.docs-code-block .highlight .sx { color: #d2bbff; }
.docs-code-block .highlight .c, .docs-code-block .highlight .c1,
.docs-code-block .highlight .cm, .docs-code-block .highlight .cs { color: #958e9e; font-style: italic; }
.docs-code-block .highlight .nb, .docs-code-block .highlight .bp { color: #ffb694; }
.docs-code-block .highlight .nf, .docs-code-block .highlight .nx { color: #c0c1ff; }
.docs-code-block .highlight .mi, .docs-code-block .highlight .mf,
.docs-code-block .highlight .mh, .docs-code-block .highlight .mo { color: #ffb694; }
.docs-code-block .highlight .o, .docs-code-block .highlight .ow { color: #e2e0fc; }
.docs-code-block .highlight .p { color: #e2e0fc; }
.docs-code-block .highlight .na { color: #d2bbff; }
.docs-code-block .highlight .nn, .docs-code-block .highlight .nc { color: #ffb694; }
```

- [ ] **Step 2: Build Tailwind and verify**

Run: `bin/rails tailwindcss:build 2>&1 | tail -3`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat: add docs typography, code blocks, tabs, and syntax highlighting styles"
```

---

## Task 5: Client-Side Search

**Files:**
- Create: `app/javascript/controllers/docs_search_controller.js`
- Modify: `app/controllers/docs_controller.rb` (add search_index action)
- Modify: `config/routes.rb` (add search index route)

- [ ] **Step 1: Add search index route**

In `config/routes.rb`, add after the docs routes:

```ruby
get "/docs", to: "docs#show", as: :docs
get "/docs/search-index.json", to: "docs#search_index", as: :docs_search_index
get "/docs/*path", to: "docs#show", as: :docs_page
```

- [ ] **Step 2: Add search_index action to DocsController**

Add to `app/controllers/docs_controller.rb`:

```ruby
def search_index
  entries = []
  Dir.glob(Rails.root.join("docs/content/**/*.md")).each do |file|
    path = file.sub(Rails.root.join("docs/content/").to_s, "").sub(".md", "")
    content = File.read(file)
    title = content.match(/^# (.+)/)&.captures&.first || path.split("/").last.titleize
    headings = content.scan(/^## (.+)/).flatten
    body = content.gsub(/^#+ /, "").gsub(/```.*?```/m, "").gsub(/:::.*?:::/m, "").gsub(/::\S+/, "").strip[0..300]
    entries << { title: title, path: path, headings: headings, excerpt: body }
  end
  render json: entries
end
```

- [ ] **Step 3: Create search controller**

Create `app/javascript/controllers/docs_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]

  connect() {
    this.index = null
    this.selectedIndex = -1

    document.addEventListener("keydown", (e) => {
      if (e.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
        e.preventDefault()
        this.inputTarget.focus()
      }
      if (e.key === "Escape") {
        this.close()
        this.inputTarget.blur()
      }
    })
  }

  async search() {
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query.length < 2) { this.close(); return }

    if (!this.index) {
      const res = await fetch("/docs/search-index.json")
      this.index = await res.json()
    }

    const results = this.index.filter(entry => {
      return entry.title.toLowerCase().includes(query) ||
             entry.headings.some(h => h.toLowerCase().includes(query)) ||
             entry.excerpt.toLowerCase().includes(query)
    }).slice(0, 8)

    this.selectedIndex = -1
    this.renderResults(results, query)
  }

  navigate(event) {
    const items = this.resultsTarget.querySelectorAll("a")
    if (!items.length) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
      this.highlightResult(items)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.highlightResult(items)
    } else if (event.key === "Enter" && this.selectedIndex >= 0) {
      event.preventDefault()
      items[this.selectedIndex].click()
    }
  }

  renderResults(results, query) {
    if (!results.length) {
      this.resultsTarget.innerHTML = `<div class="px-4 py-3 text-sm text-outline">No results for "${query}"</div>`
      this.resultsTarget.classList.remove("hidden")
      return
    }

    this.resultsTarget.innerHTML = results.map((r, i) => `
      <a href="/docs/${r.path}" class="block px-4 py-2.5 hover:bg-surface-container-high/50 transition ${i > 0 ? 'border-t border-outline-variant/10' : ''}">
        <div class="text-sm font-medium text-on-surface">${r.title}</div>
        <div class="text-xs text-outline mt-0.5 truncate">${r.excerpt.substring(0, 80)}...</div>
      </a>
    `).join("")

    this.resultsTarget.classList.remove("hidden")
  }

  highlightResult(items) {
    items.forEach((item, i) => {
      item.classList.toggle("bg-surface-container-high/50", i === this.selectedIndex)
    })
  }

  close() {
    this.resultsTarget.classList.add("hidden")
    this.selectedIndex = -1
  }
}
```

- [ ] **Step 4: Run tests and verify search in browser**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: All tests pass

Run: `bin/dev` and visit `http://localhost:3000/docs`, type in search box
Expected: Results appear as you type, keyboard navigation works

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/docs_search_controller.js app/controllers/docs_controller.rb config/routes.rb
git commit -m "$(cat <<'EOF'
feat: add client-side docs search with JSON index

- Search index generated from markdown files
- Fuzzy matching on title, headings, and body
- Keyboard navigation (/, arrow keys, enter, escape)
EOF
)"
```

---

## Task 6: Write Initial Content Pages (Getting Started + Apps + MCP)

**Files:**
- Create: `docs/content/getting-started/first-deploy.md`
- Create: `docs/content/getting-started/connect-server.md`
- Create: `docs/content/apps/create.md`
- Create: `docs/content/mcp/setup.md`

These are the most important pages for launch. Remaining pages can be filled incrementally.

- [ ] **Step 1: Create first-deploy.md**

Create `docs/content/getting-started/first-deploy.md`:

```markdown
# Your First Deploy

Deploy an app to Wokku in under 5 minutes.

## Prerequisites

- A Wokku account ([sign up](/docs/getting-started/sign-up))
- A connected server ([connect one](/docs/getting-started/connect-server))

## Deploy from a Template

The fastest way to get started — deploy a pre-configured app with one click.

:::tabs
::web-ui
1. Go to **Templates** in the sidebar
2. Browse or search for an app (e.g., Ghost, Uptime Kuma, n8n)
3. Click **Deploy**
4. Select your server and give the app a name
5. Click **Deploy** — Wokku handles the rest

::cli
```bash
# List available templates
wokku templates

# Deploy one
wokku deploy ghost --server my-server --name my-blog
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/templates/deploy \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "server_id": 1, "name": "my-blog"}'
```

::mcp
Ask Claude: *"Deploy a Ghost blog called my-blog on server 1"*

::mobile
Tap **Templates** in the bottom nav, find Ghost, tap **Deploy**, select your server, and confirm.
:::

## Deploy from GitHub

Connect a repo and deploy automatically on every push.

:::tabs
::web-ui
1. Go to **Apps → New App**
2. Click **Connect GitHub**
3. Select your repository and branch
4. Click **Create** — Wokku builds and deploys your app
5. Future pushes to that branch auto-deploy

::cli
```bash
wokku apps:create my-app --server my-server
wokku github:connect my-app --repo your-org/your-repo --branch main
```

::api
```bash
# Create the app
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'

# Connect GitHub via dashboard (OAuth flow required)
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

Then connect GitHub from the dashboard (OAuth flow).

::mobile
Tap **+** on the Apps screen, enter a name, select server. GitHub connection is available from the app detail screen.
:::

## Deploy with Git Push

Push directly to your Dokku server.

:::tabs
::web-ui
After creating an app, copy the git remote URL from the app's overview page:

```
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::cli
```bash
wokku apps:create my-app --server my-server
# Copy the git URL from the output, then:
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::api
Create the app via API, then use `git push` to deploy:

```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'

git remote add dokku dokku@your-server:my-app
git push dokku main
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

Then push with git:
```bash
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::mobile
Create the app from Mobile, then use `git push` from your terminal.
:::

## Next Steps

- [Add a custom domain](/docs/domains-ssl/custom-domains)
- [Set environment variables](/docs/apps/config)
- [Add a database](/docs/databases/create-link)
```

- [ ] **Step 2: Create connect-server.md**

Create `docs/content/getting-started/connect-server.md`:

```markdown
# Connect a Server

Connect your Dokku server to Wokku to start deploying apps.

## Prerequisites

- A VPS or dedicated server with [Dokku](https://dokku.com) installed
- SSH access to the server
- Your SSH private key

## Add a Server

:::tabs
::web-ui
1. Go to **Servers → Add Server**
2. Enter a name for your server (e.g., "production")
3. Enter the hostname or IP address
4. Set the SSH port (default: 22)
5. Paste your SSH private key
6. Click **Connect**

Wokku connects over SSH, verifies Dokku is installed, and syncs all existing apps and databases.

::cli
```bash
wokku servers:add production \
  --host dokku.example.com \
  --ssh-key ~/.ssh/id_ed25519
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/servers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production",
    "hostname": "dokku.example.com",
    "ssh_port": 22,
    "ssh_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n..."
  }'
```

::mcp
Server creation requires an SSH key, which is best done through the Web UI or CLI.

::mobile
Tap **Servers → +**, enter hostname and SSH details, then tap **Connect**.
:::

## Verify Connection

After connecting, Wokku automatically:

- Tests the SSH connection
- Detects the Dokku version
- Syncs all existing apps, databases, and domains
- Starts collecting health metrics (CPU, memory, disk)

You can check server status anytime:

:::tabs
::web-ui
Go to **Servers** and check the status indicator (green = healthy).

::cli
```bash
wokku servers
```

::api
```bash
curl https://wokku.dev/api/v1/servers/1/status \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"What's the status of my servers?"*

::mobile
Server health is shown on the Servers tab with color indicators.
:::

## Next Steps

- [Deploy your first app](/docs/getting-started/first-deploy)
- [Browse 1-click templates](/docs/templates/browse)
```

- [ ] **Step 3: Create apps/create.md**

Create `docs/content/apps/create.md`:

```markdown
# Create an App

Create a new application on one of your connected servers.

## Create

:::tabs
::web-ui
1. Go to **Apps → New App**
2. Enter an app name (lowercase, alphanumeric, hyphens allowed)
3. Select the server to deploy on
4. Optionally set the deploy branch (default: `main`)
5. Click **Create**

::cli
```bash
wokku apps:create my-app --server my-server
```

Options:
- `--server` — server name or ID (required)
- `--branch` — deploy branch (default: main)

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": 1, "deploy_branch": "main"}'
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

::mobile
Tap **+** on the Apps screen, enter a name, select your server, and tap **Create**.
:::

## App Naming Rules

- Lowercase letters, numbers, and hyphens only
- Must start with a letter
- 3-30 characters
- Must be unique per server

## After Creation

Your app is created but not yet deployed. Next steps:

1. [Deploy your code](/docs/apps/deploy) via git push or GitHub
2. [Set environment variables](/docs/apps/config) for your app
3. [Add a custom domain](/docs/domains-ssl/custom-domains)
4. [Add a database](/docs/databases/create-link) if needed
```

- [ ] **Step 4: Create mcp/setup.md**

Create `docs/content/mcp/setup.md`:

```markdown
# Claude Code (MCP) Setup

Manage your Wokku apps directly from [Claude Code](https://docs.anthropic.com/en/docs/claude-code) using natural language. 55 tools covering 100% of the Wokku API.

## Prerequisites

- A Wokku account with an API token
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Ruby 3.0+ (no gems required)

## Setup

### 1. Download the MCP server

```bash
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/mcp/server.rb -o wokku-mcp.rb
```

### 2. Get your API token

:::tabs
::web-ui
Go to **Settings → API Tokens → Create Token**. Copy the token.

::cli
```bash
wokku tokens:create --name claude-mcp
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/auth/tokens \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "claude-mcp"}'
```
:::

### 3. Add to Claude Code

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://wokku.dev/api/v1 \
  -e WOKKU_API_TOKEN=your-token-here \
  -- ruby wokku-mcp.rb
```

Or add to your project's `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "wokku": {
      "command": "ruby",
      "args": ["wokku-mcp.rb"],
      "env": {
        "WOKKU_API_URL": "https://wokku.dev/api/v1",
        "WOKKU_API_TOKEN": "your-token-here"
      }
    }
  }
}
```

### 4. Verify

Restart Claude Code and ask:

```
List my Wokku apps
```

## Example Prompts

- "List my servers and their status"
- "Deploy a Ghost blog on server 1"
- "Show me the logs for my-app"
- "Set DATABASE_URL on my-app to postgres://..."
- "Add the domain blog.example.com to my-app and enable SSL"
- "Scale my-app to 2 web dynos"
- "Rollback my-app to the previous release"
- "Create a backup of my production database"
- "Invite alice@example.com to the engineering team"
- "Set up a Slack notification for deploy failures"

## Self-Hosted

If you're running Wokku on your own server, change the API URL:

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://paas.mycompany.com/api/v1 \
  -e WOKKU_API_TOKEN=your-token \
  -- ruby wokku-mcp.rb
```

## Troubleshooting

**"Cannot connect"** — Check that `WOKKU_API_URL` is correct and the server is reachable.

**"Invalid or expired token"** — Generate a new API token from your dashboard.

**Tools not showing up** — Restart Claude Code. Run `claude mcp list` to verify the server is connected.

See [Available Tools](/docs/mcp/tools) for the full list of 55 tools.
```

- [ ] **Step 5: Create placeholder pages for remaining sections**

Create minimal placeholder `.md` files for each remaining path in `sidebar.yml` so navigation links don't 404. Each file should contain:

```markdown
# [Page Title]

Documentation coming soon.
```

Create these files:
- `docs/content/apps/deploy.md`
- `docs/content/apps/github-autodeploy.md`
- `docs/content/apps/config.md`
- `docs/content/apps/logs.md`
- `docs/content/apps/lifecycle.md`
- `docs/content/templates/browse.md`
- `docs/content/templates/deploy.md`
- `docs/content/domains-ssl/custom-domains.md`
- `docs/content/domains-ssl/ssl.md`
- `docs/content/databases/engines.md`
- `docs/content/databases/create-link.md`
- `docs/content/databases/backups.md`
- `docs/content/scaling/dynos.md`
- `docs/content/scaling/tiers.md`
- `docs/content/monitoring/logs.md`
- `docs/content/monitoring/metrics.md`
- `docs/content/monitoring/health-checks.md`
- `docs/content/monitoring/notifications.md`
- `docs/content/teams/members.md`
- `docs/content/teams/permissions.md`
- `docs/content/cli/install.md`
- `docs/content/cli/commands.md`
- `docs/content/api/authentication.md`
- `docs/content/api/endpoints.md`
- `docs/content/mcp/tools.md`
- `docs/content/mobile/download.md`
- `docs/content/mobile/notifications.md`
- `docs/content/billing/plans.md`
- `docs/content/billing/usage.md`
- `docs/content/troubleshooting/common.md`
- `docs/content/troubleshooting/faq.md`

- [ ] **Step 6: Run all tests**

Run: `bin/rails test test/controllers/docs_controller_test.rb`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add docs/content/
git commit -m "$(cat <<'EOF'
docs: add initial content pages for getting-started, apps, and MCP

- Full content: sign-up, first-deploy, connect-server, apps/create, mcp/setup
- All pages include channel tabs (Web UI, CLI, API, MCP, Mobile)
- Placeholder pages for remaining 31 sections
EOF
)"
```

---

## Task 7: Helper Tests

**Files:**
- Create: `test/helpers/docs_helper_test.rb`

- [ ] **Step 1: Write helper tests**

Create `test/helpers/docs_helper_test.rb`:

```ruby
require "test_helper"

class DocsHelperTest < ActionView::TestCase
  setup do
    @sidebar = YAML.load_file(Rails.root.join("docs/sidebar.yml"))
    @path = "getting-started/sign-up"
  end

  test "docs_active? returns true for current path" do
    assert docs_active?("getting-started/sign-up")
  end

  test "docs_active? returns false for other path" do
    refute docs_active?("apps/create")
  end

  test "docs_section_active? returns true when section contains current path" do
    section = @sidebar.find { |s| s["title"] == "Getting Started" }
    assert docs_section_active?(section)
  end

  test "docs_section_active? returns false for other section" do
    section = @sidebar.find { |s| s["title"] == "Apps" }
    refute docs_section_active?(section)
  end

  test "docs_page_title includes page title" do
    assert_match /Sign Up/, docs_page_title
    assert_match /Wokku Docs/, docs_page_title
  end
end
```

- [ ] **Step 2: Run tests**

Run: `bin/rails test test/helpers/docs_helper_test.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add test/helpers/docs_helper_test.rb
git commit -m "test: add DocsHelper unit tests"
```

---

## Task 8: Final Integration Test and Cleanup

**Files:**
- Modify: `test/controllers/docs_controller_test.rb` (add tab and search tests)

- [ ] **Step 1: Add integration tests for tabs and search**

Add to `test/controllers/docs_controller_test.rb`:

```ruby
test "tabs render with channel buttons" do
  get "/docs/getting-started/sign-up"
  assert_response :success
  assert_select ".docs-tabs"
  assert_select ".docs-tab-btn", minimum: 2
  assert_select ".docs-tab-panel", minimum: 2
end

test "search index returns JSON" do
  get "/docs/search-index.json"
  assert_response :success
  json = JSON.parse(response.body)
  assert json.is_a?(Array)
  assert json.any? { |entry| entry["path"] == "getting-started/sign-up" }
  assert json.first.key?("title")
  assert json.first.key?("headings")
  assert json.first.key?("excerpt")
end

test "code blocks have syntax highlighting" do
  get "/docs/getting-started/first-deploy"
  assert_response :success
  assert_select ".docs-code-block"
end

test "prev/next links point to correct pages" do
  get "/docs/getting-started/first-deploy"
  assert_select ".docs-prev-next a[href='/docs/getting-started/sign-up']"
  assert_select ".docs-prev-next a[href='/docs/getting-started/connect-server']"
end
```

- [ ] **Step 2: Run full test suite**

Run: `bin/rails test test/controllers/docs_controller_test.rb test/helpers/docs_helper_test.rb`
Expected: All tests pass

- [ ] **Step 3: Smoke test in browser**

Run: `bin/dev` and verify:
1. `http://localhost:3000/docs` → renders sign-up page with sidebar
2. Sidebar navigation works, sections expand/collapse
3. Channel tabs switch correctly, preference persists across pages
4. Table of contents highlights on scroll
5. Search finds results
6. Prev/next navigation works
7. Code blocks have syntax highlighting
8. Mobile: sidebar becomes hamburger drawer

- [ ] **Step 4: Commit**

```bash
git add test/controllers/docs_controller_test.rb
git commit -m "test: add integration tests for docs tabs, search, and navigation"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Gems + DocsController + routes + first markdown | 7 files |
| 2 | Docs layout + sidebar + TOC + show views | 5 files |
| 3 | Stimulus controllers (tabs, sidebar, TOC) | 3 files |
| 4 | CSS styles (typography, code blocks, tabs, syntax) | 1 file |
| 5 | Client-side search | 2 files |
| 6 | Content pages (5 full + 31 placeholders) | 36 files |
| 7 | Helper tests | 1 file |
| 8 | Integration tests + smoke test | 1 file |
