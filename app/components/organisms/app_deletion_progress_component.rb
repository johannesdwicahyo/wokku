module Organisms
  # Full-area overlay shown while AppDestroyJob deletes an app: blocks the
  # page and lists each teardown step live (Apps::DeletionProgress
  # re-renders and broadcasts it on every step).
  class AppDeletionProgressComponent < ApplicationComponent
    ICONS = { "done" => "✓", "warning" => "!", "waiting" => "…" }.freeze

    def initialize(app_id:, progress:)
      @app_id = app_id
      @progress = progress
    end

    def dom_id = "app_deletion_#{@app_id}"
    def app_name = @progress[:app_name]
    def steps = @progress[:steps]
    def finished? = @progress[:state] != "running"
    def failed? = @progress[:state] == "failed"
    def warnings? = steps.any? { |s| s[:state] == "warning" }

    def title
      return "Couldn't finish deleting #{app_name}" if failed?
      finished? ? "#{app_name} deleted" : "Deleting #{app_name}…"
    end

    def icon_classes(state)
      case state
      when "done" then "text-success"
      when "warning" then "text-warn"
      else "text-dim"
      end
    end
  end
end
