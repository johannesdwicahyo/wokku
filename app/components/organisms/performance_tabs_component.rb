module Organisms
  # Sub-nav for the Performance tab: Metrics (container CPU/mem) → Requests
  # (HTTP traffic) → Vitals (real-user web vitals). Mirrors
  # AppRuntimeComponent. Self-contained hrefs (NOT section_path, which only
  # knows the deploy/runtime/settings groups).
  class PerformanceTabsComponent < ApplicationComponent
    SECTIONS = %i[metrics requests vitals].freeze

    def initialize(app:, active: :metrics)
      @app = app
      @active = active.to_sym
    end
    attr_reader :app, :active

    def section_href(section)
      case section
      when :metrics  then helpers.dashboard_app_metrics_path(app)
      when :requests then helpers.dashboard_app_monitor_path(app)
      when :vitals   then helpers.dashboard_app_performance_path(app)
      end
    end

    def section_label(section)
      I18n.t("dashboard.performance_tabs.#{section}", default: section.to_s)
    end
  end
end
