module ApplicationHelper
  # ---------------------------------------------------------------------------
  # Section-path helpers for the Deploy / Runtime / Settings sub-nav strips.
  # Each constant maps section keys → path lambdas; section_path/3 resolves
  # a (group, app, section) triple to a URL string.
  # ---------------------------------------------------------------------------
  DEPLOY_SECTION_PATHS = ->(app) {{
    releases: -> { Rails.application.routes.url_helpers.dashboard_app_releases_path(app) },
    github:   -> { Rails.application.routes.url_helpers.dashboard_app_github_repos_path(app) },
    previews: -> { Rails.application.routes.url_helpers.dashboard_app_previews_path(app) },
    config:   -> { Rails.application.routes.url_helpers.dashboard_app_config_index_path(app) }
  }}
  RUNTIME_SECTION_PATHS = ->(app) {{
    logs:     -> { Rails.application.routes.url_helpers.dashboard_app_logs_path(app) },
    metrics:  -> { Rails.application.routes.url_helpers.dashboard_app_metrics_path(app) },
    terminal: -> { Rails.application.routes.url_helpers.dashboard_app_terminal_path(app) },
    scaling:  -> { Rails.application.routes.url_helpers.dashboard_app_scaling_path(app) }
  }}
  SETTINGS_SECTION_PATHS = ->(app) {{
    domains:         -> { Rails.application.routes.url_helpers.dashboard_app_domains_path(app) },
    checks:          -> { Rails.application.routes.url_helpers.dashboard_app_checks_path(app) },
    scheduled_tasks: -> { Rails.application.routes.url_helpers.dashboard_app_scheduled_tasks_path(app) },
    log_drains:      -> { Rails.application.routes.url_helpers.dashboard_app_log_drains_path(app) },
    transfer:        -> { Rails.application.routes.url_helpers.transfer_dashboard_app_path(app) }
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

  # Returns a signup URL pre-tagged with the chosen plan, or falls back to
  # /pricing for tiers we don't yet purchase inline. Used by the landing
  # PricingTiersComponent so a click on "Choose Pro" lands a visitor on
  # the right signup flow with the plan attribute already captured.
  def user_signup_path_for_plan(plan_key)
    new_user_registration_path(plan: plan_key)
  rescue NoMethodError
    pricing_path
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
end
