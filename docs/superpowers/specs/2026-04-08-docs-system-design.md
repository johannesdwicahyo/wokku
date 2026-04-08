# Wokku.dev Documentation System Design

**Date:** 2026-04-08
**Scope:** EE documentation at `wokku.dev/docs/*` — multi-page, markdown-powered, with channel tabs
**Audience:** Wokku.dev users (non-technical to power users). CE docs remain on GitHub.

## Problem

The current docs page is a single cramped page at `/docs` with no navigation, no structure, and no discoverability. Users have no way to find MCP setup, learn about the mobile app, or understand how to use the platform beyond basic getting started. Two user types (beginners who just want easy deploys, and developers who want CLI/API/MCP) are not served.

## Solution

A Docusaurus-like documentation system built inside the Rails app. Markdown files in the repo, rendered by Rails, with sidebar navigation, table of contents, and channel-switching tabs (Web UI / CLI / API / MCP / Mobile).

## Architecture

### File Structure

```
docs/
  content/                    # Markdown documentation files
    getting-started/
      index.md                # Section overview
      sign-up.md
      first-deploy.md
      connect-server.md
    apps/
      index.md
      create.md
      deploy.md
      github-autodeploy.md
      config.md
      logs.md
      lifecycle.md
    templates/
      index.md
      browse.md
      deploy.md
    domains-ssl/
      index.md
      custom-domains.md
      ssl.md
    databases/
      index.md
      engines.md
      create-link.md
      backups.md
    scaling/
      index.md
      dynos.md
      tiers.md
    monitoring/
      index.md
      logs.md
      metrics.md
      health-checks.md
      notifications.md
    teams/
      index.md
      members.md
      permissions.md
    cli/
      index.md
      install.md
      commands.md
    api/
      index.md
      authentication.md
      endpoints.md
    mcp/
      index.md
      setup.md
      tools.md
    mobile/
      index.md
      download.md
      notifications.md
    billing/
      index.md
      plans.md
      usage.md
    troubleshooting/
      index.md
      common.md
      faq.md
  sidebar.yml                 # Navigation structure definition
```

### Sidebar Configuration (`docs/sidebar.yml`)

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

## Channel Tabs

### Markdown Syntax

Doc authors use a custom fenced block syntax to write channel-specific content:

```markdown
## Create an App

:::tabs
::web-ui
Navigate to **Apps > New App**. Enter a name, select your server, and click **Create**.

::cli
```bash
wokku apps:create my-app --server my-server
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

::mobile
Tap **+** on the Apps screen, enter a name, select server, tap **Create**.
:::
```

### Tab Labels

| Key | Label |
|-----|-------|
| `web-ui` | Web UI |
| `cli` | CLI |
| `api` | API |
| `mcp` | Claude Code |
| `mobile` | Mobile |

### Tab Behavior

- Tabs render as a horizontal tab bar above the content block
- Clicking a tab shows that channel's content, hides others
- **Selection persists** across the page and across pages via `localStorage` key `wokku-docs-channel`
- If a `:::tabs` block omits a channel (e.g., no `::mobile`), that tab is hidden for that block only
- Default channel is `web-ui` for new visitors

### Preprocessing

The custom `:::tabs` / `::channel` / `:::` syntax is preprocessed before markdown rendering:

1. Regex splits `:::tabs` blocks into per-channel content
2. Each channel's content is rendered as markdown independently
3. Output is wrapped in a `div[data-controller="docs-tabs"]` with `div[data-tab="web-ui"]` etc.
4. Stimulus controller handles show/hide and localStorage persistence

## Rails Components

### Routes

```ruby
# In config/routes.rb
get "docs", to: "docs#show", as: :docs_root
get "docs/*path", to: "docs#show", as: :docs_page
```

### Controller (`app/controllers/docs_controller.rb`)

```ruby
class DocsController < ApplicationController
  layout "docs"

  skip_before_action :authenticate_user!, if: -> { true }

  def show
    @path = params[:path] || "getting-started/sign-up"
    @sidebar = load_sidebar
    @content = render_doc(@path)
    @toc = extract_toc(@content)
    @prev_page, @next_page = find_prev_next(@path)
  end

  private

  def load_sidebar
    YAML.load_file(Rails.root.join("docs/sidebar.yml"))
  end

  def render_doc(path)
    file = Rails.root.join("docs/content/#{path}.md")
    raise ActiveRecord::RecordNotFound unless file.exist?

    raw = file.read
    processed = preprocess_tabs(raw)
    render_markdown(processed)
  end

  def preprocess_tabs(content)
    # Transform :::tabs blocks into HTML with data attributes
    # Returns HTML string with tab containers
  end

  def render_markdown(text)
    # Commonmarker or Redcarpet rendering with:
    # - GFM tables
    # - Fenced code blocks
    # - Syntax highlighting via Rouge
    # - Auto-linked headings (for TOC)
    # - ID anchors on h2/h3
  end

  def extract_toc(html)
    # Parse rendered HTML for h2/h3 tags
    # Return array of { level:, text:, id: }
  end

  def find_prev_next(path)
    # Flatten sidebar items, find current index
    # Return [prev, next] or nil at boundaries
  end
end
```

### Layout (`app/views/layouts/docs.html.erb`)

Three-column layout:

```
┌─────────────────────────────────────────────────────────┐
│  Header: Logo + Search + Sign In                         │
├────────────┬────────────────────────────┬───────────────┤
│  Sidebar   │  Content                   │ On This Page  │
│  (240px)   │  (flexible)                │ (200px)       │
│            │                            │               │
│  Collapsible sections                   │ TOC from h2/h3│
│  with icons                             │               │
│  Current page highlighted               │               │
│            │                            │               │
├────────────┴────────────────────────────┴───────────────┤
│  Footer: ← Prev Page    |    Next Page →                │
└─────────────────────────────────────────────────────────┘
```

- Sidebar collapses to hamburger on mobile (< 768px)
- Right TOC hides on tablet (< 1024px)
- Search bar uses client-side JSON index

### Stimulus Controller (`app/javascript/controllers/docs_tabs_controller.js`)

```javascript
// Handles tab switching within :::tabs blocks
// - Reads/writes localStorage("wokku-docs-channel")
// - On connect: applies saved preference
// - On tab click: switches all tab blocks on the page
// - Shows first available tab if preferred channel not in block
```

### Search

Client-side search over a JSON index:

- Generated at boot (or via rake task) by scanning all `.md` files
- Each entry: `{ title, path, headings[], body_excerpt }`
- Stored as `/docs/search-index.json` (cached)
- Search UI: input in header, dropdown results with fuzzy matching
- Stimulus controller for search interaction

## Gems Required

| Gem | Purpose |
|-----|---------|
| `commonmarker` | GFM markdown rendering (fast, C-based) |
| `rouge` | Syntax highlighting for code blocks |

Both are standard, well-maintained, and have no heavy dependencies.

## UI Design

### Sidebar

- Dark background matching the app's `surface-container` palette
- Sections with Material Symbols icons
- Collapsible sections (expand current, collapse others)
- Active page highlighted with `primary` color left border
- Smooth transitions on expand/collapse

### Content Area

- Clean white/surface background
- Comfortable reading width (max ~720px prose)
- Code blocks with copy button and syntax highlighting
- Channel tabs: pill-style buttons, active tab in `primary` color
- Headings with hover-to-show anchor links
- Tables styled consistently with the rest of the app
- Callout blocks for tips, warnings, notes (via `> [!NOTE]` GFM syntax)

### Table of Contents (right rail)

- Sticky, scrolls with page
- Highlights current section based on scroll position (Intersection Observer)
- `h2` items bold, `h3` items indented

### Prev/Next Footer

- Full-width bar at bottom of content
- Left: previous page title with left arrow
- Right: next page title with right arrow
- Derived from sidebar order

### Mobile

- Sidebar becomes a slide-out drawer (hamburger icon in header)
- TOC hidden, replaced by a "On this page" expandable at top of content
- Tabs stack vertically if more than 3 channels

## Caching

- Fragment cache each rendered markdown page keyed on file mtime
- Sidebar YAML cached at boot, busted on file change
- Search index regenerated via `rails docs:index` or on deploy
- In development: no caching, live reload on file changes

## Section Content Overview

Each section covers these channels where applicable: Web UI, CLI, API, MCP, Mobile.

| Section | Pages | Key Content |
|---------|-------|-------------|
| Getting Started | 3 | Sign up, first deploy walkthrough, connect Dokku server |
| Apps | 6 | Create, deploy (git push, GitHub, Docker), config vars, logs, start/stop/restart |
| Templates | 2 | Browse 100+ templates, 1-click deploy |
| Domains & SSL | 2 | Add custom domains, auto Let's Encrypt |
| Databases | 3 | 9 engines, create/link/unlink, scheduled + on-demand backups |
| Scaling | 2 | Web/worker dynos, dyno tiers and resource limits |
| Monitoring | 4 | Real-time logs, CPU/memory metrics, health checks config, notification channels |
| Teams | 2 | Invite members, viewer/member/admin roles |
| CLI | 2 | Installation, 50+ commands reference |
| API | 2 | Token auth, all endpoints reference |
| MCP | 2 | Claude Code setup, 55 tools reference |
| Mobile | 2 | Download links, push notification setup |
| Billing | 2 | Plans comparison, usage tracking (EE only) |
| Troubleshooting | 2 | Common issues, FAQ |
| **Total** | **36 pages** | |

## Not In Scope

- Versioned docs (v1/v2) — not needed yet
- i18n / translations — future
- User comments / feedback on pages — future
- Edit on GitHub links — future (easy to add)
- Blog / changelog — separate concern
- Video tutorials — future enhancement

## Migration

The current single-page `/docs` view (`app/views/pages/docs.html.erb`) will be replaced by a redirect to `/docs/getting-started/sign-up`. The `PagesController#docs` action and its view are removed. The route `get "/docs"` is updated to point to `DocsController#show`.
