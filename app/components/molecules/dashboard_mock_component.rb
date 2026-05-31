module Molecules
  class DashboardMockComponent < ApplicationComponent
    APPS = [
      { name: "my-rails-app", icon: "rubyonrails",         size: "Performance", domain: "app.example.cloud" },
      { name: "ghost-blog",   icon: "ghost",               size: "Standard",    domain: "blog.example.cloud" },
      { name: "n8n-flows",    icon: "n8n",                 size: "Basic",       domain: "flow.example.cloud" },
      { name: "next-shop",    icon: "nextdotjs",           size: "Performance", domain: "shop.example.cloud" },
      { name: "fastapi-svc",  icon: "fastapi",             size: "Basic",       domain: "api.example.cloud" },
      { name: "plausible",    icon: "plausibleanalytics",  size: "Basic",       domain: "stat.example.cloud" },
    ].freeze

    SIDE_ITEMS = ["◆ Apps", "◷ Databases", "⌖ Domains", "✦ Templates", "⎘ Logs", "⚙ Settings"].freeze
    FAVORITES  = ["● my-rails-app", "● ghost-blog", "● n8n-flows"].freeze

    def apps; APPS; end
    def side_items; SIDE_ITEMS; end
    def favorites; FAVORITES; end
  end
end
