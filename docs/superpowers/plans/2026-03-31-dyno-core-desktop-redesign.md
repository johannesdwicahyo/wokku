# Dyno Core Desktop Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current green/slate dashboard UI with the Dyno Core "Orchestrator Console" design system — deep purple/indigo theme, fixed left sidebar, Space Grotesk + Inter + JetBrains Mono typography, glass panels, and Material Symbols icons.

**Architecture:** Phase 1 implements the design foundation: Tailwind theme config, layout shell (sidebar + top bar), and shared partials. All existing page content renders inside the new shell with correct colors. Phases 2-5 (separate plans) redesign individual pages to match the Stitch screen designs.

**Tech Stack:** Rails 8.1, Tailwind CSS 4, ERB views, Turbo/Stimulus, Google Material Symbols, Space Grotesk + Inter + JetBrains Mono fonts

**Reference:** Stitch HTML files at `/tmp/stitch-desktop-dashboard.html` (sidebar, header, color tokens, component patterns)

---

## File Map

| Task | Files Created/Modified | Purpose |
|------|----------------------|---------|
| 1 | Create: `app/assets/tailwind/application.css` | Tailwind theme with Dyno Core color tokens + utility classes |
| 2 | Modify: `app/views/layouts/dashboard.html.erb` | New layout shell with fonts, meta, sidebar + header structure |
| 3 | Rewrite: `app/views/dashboard/shared/_sidebar.html.erb` | Dyno Core sidebar with Material Symbols icons |
| 4 | Rewrite: `app/views/dashboard/shared/_navbar.html.erb` | Dyno Core top header bar (search, notifications, deploy, avatar) |
| 5 | Modify: `app/views/dashboard/shared/_flash.html.erb` | Flash messages in Dyno Core colors |
| 6 | Modify: `app/views/dashboard/apps/_tabs.html.erb` | App detail tabs in Dyno Core style |
| 7 | Modify: `app/views/dashboard/shared/_slide_panel.html.erb` | Slide panel in Dyno Core style |

---

### Task 1: Tailwind Theme — Dyno Core Color Tokens & Utilities

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Replace Tailwind CSS with Dyno Core theme**

Replace the contents of `app/assets/tailwind/application.css` with:

```css
@import "tailwindcss";

@theme {
  /* === Dyno Core Design System === */

  /* Surface hierarchy (dark to light) */
  --color-surface: #111125;
  --color-surface-dim: #111125;
  --color-surface-bright: #37374d;
  --color-surface-container-lowest: #0c0c1f;
  --color-surface-container-low: #1a1a2e;
  --color-surface-container: #1e1e32;
  --color-surface-container-high: #28283d;
  --color-surface-container-highest: #333348;
  --color-surface-variant: #333348;
  --color-surface-tint: #c0c1ff;

  /* Primary */
  --color-primary: #c0c1ff;
  --color-primary-container: #2c2e68;
  --color-primary-fixed: #e1e0ff;
  --color-primary-fixed-dim: #c0c1ff;
  --color-on-primary: #282a64;
  --color-on-primary-container: #9597d9;
  --color-on-primary-fixed: #12124e;
  --color-on-primary-fixed-variant: #3f417c;

  /* Secondary */
  --color-secondary: #d2bbff;
  --color-secondary-container: #5625ab;
  --color-secondary-fixed: #eaddff;
  --color-secondary-fixed-dim: #d2bbff;
  --color-on-secondary: #3e008e;
  --color-on-secondary-container: #c3a6ff;
  --color-on-secondary-fixed: #25005a;
  --color-on-secondary-fixed-variant: #5625ab;

  /* Tertiary */
  --color-tertiary: #ffb694;
  --color-tertiary-container: #5d2200;
  --color-tertiary-fixed: #ffdbcc;
  --color-tertiary-fixed-dim: #ffb694;
  --color-on-tertiary: #571f00;
  --color-on-tertiary-container: #de875c;
  --color-on-tertiary-fixed: #351000;
  --color-on-tertiary-fixed-variant: #75340f;

  /* Error */
  --color-error: #ffb4ab;
  --color-error-container: #93000a;
  --color-on-error: #690005;
  --color-on-error-container: #ffdad6;

  /* Neutral / Surface text */
  --color-background: #111125;
  --color-on-background: #e2e0fc;
  --color-on-surface: #e2e0fc;
  --color-on-surface-variant: #ccc3d5;
  --color-outline: #958e9e;
  --color-outline-variant: #4a4453;

  /* Inverse */
  --color-inverse-surface: #e2e0fc;
  --color-inverse-on-surface: #2f2e43;
  --color-inverse-primary: #565995;

  /* Typography */
  --font-headline: "Space Grotesk", system-ui, sans-serif;
  --font-body: "Inter", system-ui, sans-serif;
  --font-label: "Inter", system-ui, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, monospace;

  /* Border radius — sharp, engineered */
  --radius-sm: 0.125rem;
  --radius-md: 0.25rem;
  --radius-lg: 0.5rem;
  --radius-xl: 0.75rem;
}

/* === Utility Classes === */

/* Material Symbols setup */
.material-symbols-outlined {
  font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}

/* Glass panel effect for modals and floating elements */
.glass-panel {
  background: rgba(55, 55, 77, 0.8);
  backdrop-filter: blur(20px);
}

/* Signature gradient for CTAs and "Deploying" states */
.technical-gradient {
  background: linear-gradient(135deg, #c0c1ff 0%, #5625ab 100%);
}

/* Glow badge for "Running" status */
.glow-running {
  box-shadow: 0 0 8px rgba(195, 166, 255, 0.4);
}

/* Glow badge for "Error" status */
.glow-error {
  box-shadow: 0 0 8px rgba(255, 180, 171, 0.4);
}

/* Ghost border — felt, not seen */
.ghost-border {
  border-color: rgba(74, 68, 83, 0.15);
}

/* Custom scrollbar for dark theme */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #4a4453; border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: #958e9e; }
```

- [ ] **Step 2: Verify Tailwind builds**

Run:
```bash
bin/rails tailwindcss:build
```

Expected: No errors, builds successfully.

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat: add Dyno Core design system theme tokens to Tailwind"
```

---

### Task 2: Dashboard Layout Shell

**Files:**
- Modify: `app/views/layouts/dashboard.html.erb`

- [ ] **Step 1: Replace the dashboard layout**

Replace the entire file with:

```erb
<!DOCTYPE html>
<html class="dark h-full" lang="en">
  <head>
    <title><%= content_for(:title) || "Wokku" %></title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Wokku">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" rel="stylesheet">

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.min.css">
    <%= javascript_importmap_tags %>
  </head>

  <body class="h-full bg-surface text-on-surface font-body selection:bg-primary-container selection:text-primary">
    <%= render "dashboard/shared/sidebar" %>
    <%= render "dashboard/shared/navbar" %>

    <main class="ml-64 pt-16 min-h-screen">
      <div class="px-8 py-8">
        <%= render "dashboard/shared/flash" %>
        <%= yield %>
      </div>
    </main>
  </body>
</html>
```

- [ ] **Step 2: Verify the page loads**

Run:
```bash
bin/rails server
```

Visit `http://localhost:3000/dashboard/apps`. The layout should render with the new Dyno Core background colors and fonts. Content will still use old color classes — that's expected. The shell (sidebar + header) will be updated in the next tasks.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/dashboard.html.erb
git commit -m "feat: update dashboard layout shell with Dyno Core fonts and colors"
```

---

### Task 3: Sidebar Navigation

**Files:**
- Rewrite: `app/views/dashboard/shared/_sidebar.html.erb`

- [ ] **Step 1: Replace the sidebar**

Replace the entire file with:

```erb
<aside class="fixed left-0 top-0 bottom-0 w-64 bg-surface-container-lowest flex flex-col h-full py-6 z-20">
  <%# Brand %>
  <div class="px-6 mb-8">
    <a href="<%= root_path %>" class="block">
      <h1 class="text-lg font-black text-white font-headline tracking-tight">Wokku</h1>
      <p class="text-xs text-outline font-label mt-0.5"><%= current_team&.name || "Dashboard" %></p>
    </a>
  </div>

  <%# Main Navigation %>
  <%
    nav_items = [
      { name: "Dashboard", path: dashboard_apps_path, pattern: "/dashboard/apps", icon: "dashboard", exact: true },
      { name: "Apps", path: dashboard_apps_path, pattern: "/dashboard/apps", icon: "apps" },
      { name: "Templates", path: dashboard_templates_path, pattern: "/dashboard/templates", icon: "storefront" },
      { name: "Servers", path: dashboard_servers_path, pattern: "/dashboard/servers", icon: "dns" },
      { name: "Activity", path: dashboard_activities_path, pattern: "/dashboard/activities", icon: "history" },
    ]
  %>
  <nav class="flex-1 space-y-0.5">
    <% nav_items.each do |item| %>
      <%
        active = request.path.start_with?(item[:pattern])
        active_classes = "text-primary bg-surface-container-high border-r-2 border-primary font-semibold"
        inactive_classes = "text-outline hover:text-on-surface-variant hover:bg-surface transition-all"
      %>
      <a href="<%= item[:path] %>" class="flex items-center px-6 py-3 text-sm font-label <%= active ? active_classes : inactive_classes %>">
        <span class="material-symbols-outlined mr-3 text-[20px]"><%= item[:icon] %></span>
        <span class="font-medium"><%= item[:name] %></span>
      </a>
    <% end %>
  </nav>

  <%# Bottom links %>
  <div class="mt-auto px-6 pt-6 border-t border-outline-variant/10 space-y-1">
    <a href="<%= dashboard_notifications_path %>" class="flex items-center py-2 text-outline hover:text-on-surface-variant transition-all">
      <span class="material-symbols-outlined mr-3 text-[18px]">notifications</span>
      <span class="text-xs font-medium font-label">Notifications</span>
    </a>
    <a href="<%= dashboard_teams_path %>" class="flex items-center py-2 text-outline hover:text-on-surface-variant transition-all">
      <span class="material-symbols-outlined mr-3 text-[18px]">group</span>
      <span class="text-xs font-medium font-label">Teams</span>
    </a>
    <a href="<%= dashboard_profile_path %>" class="flex items-center py-2 text-outline hover:text-on-surface-variant transition-all">
      <span class="material-symbols-outlined mr-3 text-[18px]">settings</span>
      <span class="text-xs font-medium font-label">Settings</span>
    </a>
  </div>
</aside>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/shared/_sidebar.html.erb
git commit -m "feat: replace sidebar with Dyno Core design — Material Symbols, purple theme"
```

---

### Task 4: Top Header Bar

**Files:**
- Rewrite: `app/views/dashboard/shared/_navbar.html.erb`

- [ ] **Step 1: Replace the navbar**

Replace the entire file with:

```erb
<header class="fixed top-0 right-0 left-64 h-16 bg-surface border-b border-surface-container-high/30 flex items-center justify-between px-8 z-10">
  <%# Left: Search %>
  <div class="flex items-center gap-4">
    <div class="relative">
      <span class="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
      <input type="text" placeholder="Search resources..." class="bg-surface-container-low border-none rounded-md pl-10 pr-4 py-1.5 text-sm focus:ring-1 focus:ring-primary w-64 text-on-surface placeholder:text-outline font-body">
    </div>
  </div>

  <%# Right: Actions + User %>
  <div class="flex items-center gap-4">
    <%# Team selector %>
    <% if user_teams.size > 1 %>
      <div class="relative" data-controller="dropdown">
        <button data-action="click->dropdown#toggle" class="flex items-center gap-2 text-outline hover:text-on-surface-variant text-xs bg-surface-container rounded-md px-3 py-1.5 transition cursor-pointer font-mono">
          <%= current_team&.name || "Team" %>
          <span class="material-symbols-outlined text-[16px]">expand_more</span>
        </button>
        <div data-dropdown-target="menu" class="hidden absolute right-0 mt-1 w-48 bg-surface-container-high rounded-md shadow-xl border border-outline-variant/20 z-50">
          <% user_teams.each do |team| %>
            <a href="<%= root_path(team_id: team.id) %>" class="block px-3 py-2 text-sm text-on-surface-variant hover:bg-surface-container-highest hover:text-on-surface first:rounded-t-md last:rounded-b-md cursor-pointer transition">
              <%= team.name %>
            </a>
          <% end %>
        </div>
      </div>
    <% end %>

    <%# Quick actions %>
    <button class="text-outline hover:bg-surface-container-high p-2 rounded-md transition-colors">
      <span class="material-symbols-outlined text-[20px]">terminal</span>
    </button>
    <button class="text-outline hover:bg-surface-container-high p-2 rounded-md transition-colors">
      <span class="material-symbols-outlined text-[20px]">notifications</span>
    </button>

    <%# Deploy button %>
    <%= link_to dashboard_templates_path, class: "technical-gradient text-on-primary font-bold px-5 py-1.5 rounded-md hover:opacity-90 active:scale-95 transition-all text-sm" do %>
      Deploy
    <% end %>

    <%# User avatar %>
    <div class="relative" data-controller="dropdown">
      <button data-action="click->dropdown#toggle" class="h-8 w-8 rounded-lg bg-primary-container flex items-center justify-center overflow-hidden border border-outline-variant/30 cursor-pointer">
        <% if current_user.avatar_url.present? %>
          <img src="<%= current_user.avatar_url %>" alt="Avatar" class="w-full h-full object-cover">
        <% else %>
          <span class="text-primary text-xs font-bold font-headline"><%= current_user.email[0].upcase %></span>
        <% end %>
      </button>
      <div data-dropdown-target="menu" class="hidden absolute right-0 mt-1 w-56 bg-surface-container-high rounded-md shadow-xl border border-outline-variant/20 z-50">
        <div class="px-3 py-2.5 border-b border-outline-variant/20">
          <p class="text-xs text-on-surface font-medium truncate"><%= current_user.email %></p>
          <p class="text-xs text-outline font-mono mt-0.5"><%= current_user.role %></p>
        </div>
        <a href="<%= dashboard_profile_path %>" class="block px-3 py-2 text-sm text-on-surface-variant hover:bg-surface-container-highest hover:text-on-surface cursor-pointer transition">Profile</a>
        <%= link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "block px-3 py-2 text-sm text-on-surface-variant hover:bg-surface-container-highest hover:text-on-surface rounded-b-md cursor-pointer transition" %>
      </div>
    </div>
  </div>
</header>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/shared/_navbar.html.erb
git commit -m "feat: replace navbar with Dyno Core header — search, gradient deploy button, Material Symbols"
```

---

### Task 5: Flash Messages

**Files:**
- Modify: `app/views/dashboard/shared/_flash.html.erb`

- [ ] **Step 1: Read and replace the flash partial**

Read the current file first, then replace it with:

```erb
<% flash.each do |type, message| %>
  <% next if message.blank? %>
  <%
    classes = case type.to_s
    when "notice", "success"
      "bg-secondary-container/20 border-secondary/30 text-on-secondary-container"
    when "alert", "error"
      "bg-error-container/20 border-error/30 text-on-error-container"
    else
      "bg-surface-container-high border-outline-variant/30 text-on-surface"
    end
  %>
  <div class="mb-6 px-4 py-3 rounded-md border <%= classes %> flex items-center justify-between" data-controller="flash" data-flash-target="message">
    <div class="flex items-center gap-3">
      <% if type.to_s.in?(["notice", "success"]) %>
        <span class="material-symbols-outlined text-secondary text-[20px]">check_circle</span>
      <% else %>
        <span class="material-symbols-outlined text-error text-[20px]">error</span>
      <% end %>
      <p class="text-sm"><%= message %></p>
    </div>
    <button data-action="click->flash#dismiss" class="text-outline hover:text-on-surface transition cursor-pointer">
      <span class="material-symbols-outlined text-[18px]">close</span>
    </button>
  </div>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/shared/_flash.html.erb
git commit -m "feat: update flash messages with Dyno Core colors and Material Symbols"
```

---

### Task 6: App Detail Tabs

**Files:**
- Modify: `app/views/dashboard/apps/_tabs.html.erb`

- [ ] **Step 1: Replace the tabs partial**

Replace the entire file with:

```erb
<div class="mb-6">
  <div class="flex items-center space-x-3 mb-1">
    <%= link_to "Apps", dashboard_apps_path, class: "text-sm text-outline hover:text-primary transition" %>
    <span class="material-symbols-outlined text-outline-variant text-[16px]">chevron_right</span>
    <span class="text-sm text-on-surface font-medium font-mono"><%= app.name %></span>
  </div>
</div>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold text-on-surface font-headline"><%= app.name %></h1>
</div>

<div class="border-b border-outline-variant/15 mb-6">
  <nav class="-mb-px flex space-x-6">
    <%
      tabs = [
        { name: "Overview", path: dashboard_app_path(app), exact: true },
        { name: "Resources", path: dashboard_app_resources_path(app) },
        { name: "Config", path: dashboard_app_config_index_path(app) },
        { name: "Domains", path: dashboard_app_domains_path(app) },
        { name: "Releases", path: dashboard_app_releases_path(app) },
        { name: "Scaling", path: dashboard_app_scaling_path(app) },
        { name: "Logs", path: dashboard_app_logs_path(app) },
        { name: "Metrics", path: dashboard_app_metrics_path(app) },
      ]
    %>
    <% tabs.each do |tab| %>
      <%
        active = tab[:exact] ? request.path == tab[:path] : request.path.start_with?(tab[:path])
        classes = active ?
          "border-b-2 border-primary text-primary py-3 text-sm font-medium font-label" :
          "border-b-2 border-transparent text-outline hover:text-primary hover:border-outline-variant/30 py-3 text-sm font-medium font-label transition"
      %>
      <%= link_to tab[:name], tab[:path], class: classes %>
    <% end %>
  </nav>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/apps/_tabs.html.erb
git commit -m "feat: update app detail tabs with Dyno Core styling"
```

---

### Task 7: Slide Panel

**Files:**
- Modify: `app/views/dashboard/shared/_slide_panel.html.erb`

- [ ] **Step 1: Read and replace the slide panel**

Read the current file first, then replace with:

```erb
<%# Backdrop %>
<div data-slide-panel-target="backdrop"
     data-action="click->slide-panel#backdropClick"
     class="hidden fixed inset-0 z-40 bg-black/50 opacity-0 transition-opacity duration-300">
</div>

<%# Panel %>
<div data-slide-panel-target="panel"
     class="fixed inset-y-0 right-0 z-50 w-full max-w-md bg-surface-container-lowest border-l border-outline-variant/20 shadow-2xl transform translate-x-full transition-transform duration-300 ease-out overflow-y-auto">
  <div class="flex items-center justify-between px-6 py-4 border-b border-outline-variant/15">
    <div>
      <h2 class="text-base font-semibold text-on-surface font-headline"><%= title %></h2>
      <% if local_assigns[:subtitle] %>
        <p class="mt-0.5 text-xs text-outline"><%= subtitle %></p>
      <% end %>
    </div>
    <button data-action="click->slide-panel#close" class="text-outline hover:text-on-surface transition cursor-pointer p-1" aria-label="Close panel">
      <span class="material-symbols-outlined text-[20px]">close</span>
    </button>
  </div>

  <div class="px-6 py-5">
    <%= yield %>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/dashboard/shared/_slide_panel.html.erb
git commit -m "feat: update slide panel with Dyno Core styling"
```

---

## What This Plan Does NOT Cover (Future Phases)

These are separate plans to write after Phase 1 is deployed and validated:

- **Phase 2: Dashboard page** — Redesign apps index with metrics bar, deployment cards, system logs, traffic insights (from `/tmp/stitch-desktop-dashboard.html`)
- **Phase 3: App Detail page** — Redesign app show + all tab views (overview, resources, config, domains, releases, scaling, logs, metrics) to match `/tmp/stitch-desktop-app-detail.html`
- **Phase 4: Marketplace/Templates** — Redesign template browser with category filters and search (from `/tmp/stitch-desktop-marketplace.html`)
- **Phase 5: Settings & Billing** — Redesign profile, billing, payment methods, API keys (from `/tmp/stitch-desktop-settings.html`)

Each phase should be its own plan with its own tasks, as they are independent feature areas that can be worked on separately.

---

## Post-Phase-1 Validation Checklist

After all 7 tasks are complete, manually verify:

1. Dashboard layout loads with purple/indigo background (`#111125`)
2. Left sidebar shows with Material Symbols icons and Wokku branding
3. Top header has search bar, Deploy gradient button, user avatar dropdown
4. Sidebar navigation highlights the active page in `#c0c1ff`
5. App detail pages show tabs with purple active indicator
6. Flash messages render with secondary/error colors
7. Slide panels render with Dyno Core dark theme
8. All existing functionality (create app, deploy, scale, etc.) still works
9. Text is readable — `#e2e0fc` on `#111125` background
10. Fonts load: Space Grotesk for headlines, Inter for body, JetBrains Mono for code
