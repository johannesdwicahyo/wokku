module ApplicationHelper
  # Cloud-only copy/links/features: see Wokku.cloud?.
  def wokku_cloud? = Wokku.cloud?

  # ---------------------------------------------------------------------------
  # Section-path helpers for the Deploy / Runtime / Settings sub-nav strips.
  # Each constant maps section keys → path lambdas; section_path/3 resolves
  # a (group, app, section) triple to a URL string.
  # ---------------------------------------------------------------------------
  DEPLOY_SECTION_PATHS = ->(app) { {
    releases: -> { Rails.application.routes.url_helpers.dashboard_app_releases_path(app) },
    github:   -> { Rails.application.routes.url_helpers.dashboard_app_github_repos_path(app) },
    previews: -> { Rails.application.routes.url_helpers.dashboard_app_previews_path(app) },
    config:   -> { Rails.application.routes.url_helpers.dashboard_app_config_index_path(app) }
  }}
  RUNTIME_SECTION_PATHS = ->(app) { {
    logs:     -> { Rails.application.routes.url_helpers.dashboard_app_logs_path(app) },
    metrics:  -> { Rails.application.routes.url_helpers.dashboard_app_metrics_path(app) },
    terminal: -> { Rails.application.routes.url_helpers.dashboard_app_terminal_path(app) },
    # scaling#show is a dead-end redirect shell (ScalingController#show
    # just redirects to Resources — process/box scaling now lives there).
    # Point the sub-tab straight at the live page so it doesn't round-trip
    # through the redirect (U5 Task 4, bug 3c).
    scaling:  -> { Rails.application.routes.url_helpers.dashboard_app_resources_path(app) }
  }}
  SETTINGS_SECTION_PATHS = ->(app) { {
    domains:         -> { Rails.application.routes.url_helpers.dashboard_app_domains_path(app) },
    checks:          -> { Rails.application.routes.url_helpers.dashboard_app_checks_path(app) },
    scheduled_tasks: -> { Rails.application.routes.url_helpers.dashboard_app_scheduled_tasks_path(app) },
    transfer:        -> { Rails.application.routes.url_helpers.transfer_dashboard_app_path(app) },
    danger:          -> { Rails.application.routes.url_helpers.danger_dashboard_app_path(app) }
  }}

  # Resolves (group, app, section) to a URL string.
  # group: :deploy | :runtime | :settings
  def section_path(group, app, section)
    paths = {
      deploy:   DEPLOY_SECTION_PATHS,
      runtime:  RUNTIME_SECTION_PATHS,
      settings: SETTINGS_SECTION_PATHS
    }.fetch(group)
    paths.call(app).fetch(section).call
  end

  # The user-facing box vocabulary (sleeping/small/medium/large/xlarge) for
  # tier-backed allocations, or the "0.5 vCPU · 1 GB" shape label for
  # per-resource-shape allocations (dyno_tier nil) — see
  # DynoAllocation#size_label. Shared by AppsTableComponent's SIZE column
  # and the record panel so both stay in sync with one source of truth.
  def box_label_for(app)
    alloc = app.dyno_allocations.find { |d| d.process_type == "web" }
    return "—" unless alloc

    alloc.size_label
  end

  # Flash keys that are reserved exclusively for the PostHog analytics
  # bridge (shared/_analytics.html.erb). They must NEVER be rendered as
  # visible user toasts. Defined as a module-level constant so it can be
  # referenced safely from ERB templates (ERB compiles to method bodies
  # where Ruby disallows constant assignment).
  ANALYTICS_FLASH_KEYS = %w[posthog_event posthog_props].freeze

  # Returns true when the given flash key is an analytics-only key that
  # should never appear as a visible toast. Used by dashboard/shared/_flash.
  def analytics_flash_key?(key)
    ANALYTICS_FLASH_KEYS.include?(key.to_s)
  end

  # Brand icon for a template card. Prefers the simpleicons SVG when
  # the template declares `# icon_slug:` (real framework logo), falls
  # back to the legacy emoji table on `# icon:`.
  def template_brand_icon(template, size: 28)
    if template[:icon_slug].present?
      color = template[:icon_color].presence || "FFFFFF"
      tag.img(
        src: "https://cdn.simpleicons.org/#{template[:icon_slug]}/#{color}",
        alt: "#{template[:name]} logo",
        width: size,
        height: size,
        loading: "lazy",
        class: "block"
      )
    else
      tag.span(template_icon(template[:icon]), class: "text-xl")
    end
  end

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

  # Servers hosting the current team's apps that wokkud says are sick.
  # Powers shared/_host_down_banner. Cheap: one indexed query, only on
  # dashboard layouts.
  def unhealthy_team_servers
    return Server.none unless respond_to?(:current_team) && current_team

    Server.where(id: AppRecord.where(team: current_team).select(:server_id).distinct)
          .where(heartbeat_status: %w[degraded down])
  end

  def log_line_class(line)
    case log_line_level(line)
    when "error" then "text-red-400"
    when "warn"  then "text-yellow-500"
    when "nginx" then "text-blue-400"
    else              "text-gray-400"
    end
  end

  # Coarse level classification used both for color (log_line_class) and
  # for client-side filtering via the data-log-level attribute. Kept
  # deliberately simple — most container logs aren't structured.
  def log_line_level(line)
    if line.match?(/error|fatal|panic/i)
      "error"
    elsif line.match?(/warn/i)
      "warn"
    elsif line.match?(/nginx/i)
      "nginx"
    else
      "info"
    end
  end

  # OAuth providers whose credentials the operator actually configured —
  # the sign-in page renders buttons only for these, and falls back to
  # email+password when none are set (fresh self-host: the installer
  # seeds the admin with a password). Cloud configures all four.
  OAUTH_PROVIDER_ENV = {
    github: "GITHUB_OAUTH_CLIENT_ID",
    google_oauth2: "GOOGLE_OAUTH_CLIENT_ID",
    gitlab: "GITLAB_OAUTH_CLIENT_ID",
    bitbucket: "BITBUCKET_OAUTH_CLIENT_ID"
  }.freeze

  def configured_oauth_providers
    providers = OAUTH_PROVIDER_ENV.select { |_, env| ENV[env].present? }.keys
    # Apple needs four values (Services ID, team, key id, key), not one client id.
    providers << :apple if ::Apple::Config.web_configured?
    providers
  end

  # Host-app hook point: render a partial only when some view path
  # provides it. Managed supplies these (analytics, billing banners); a
  # standalone engine skips them silently.
  def optional_partial(path)
    render(path) if lookup_context.exists?(path, [], true)
  end
end
