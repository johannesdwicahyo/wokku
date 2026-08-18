module Atoms
  # Status pill with optional pulse animation when status=running.
  class StatusPillComponent < ApplicationComponent
    STATUSES = {
      "running"   => { label: "Running",   color: "bg-success-soft text-success", dot_color: "var(--color-success)" },
      "deploying" => { label: "Deploying", color: "bg-accent-soft text-accent",   dot_color: "var(--color-accent)" },
      "crashed"   => { label: "Crashed",   color: "bg-danger-soft text-danger",   dot_color: "var(--color-danger)" },
      "stopped"   => { label: "Stopped",   color: "bg-bg-deep text-ink-soft",     dot_color: "var(--color-dim)" },
      "sleeping"  => { label: "Sleeping",  color: "bg-warn-soft text-warn",       dot_color: "var(--color-warn)" }
    }.freeze

    def initialize(status:)
      @status = status.to_s
      @spec   = STATUSES.fetch(@status, STATUSES["stopped"])
    end
    attr_reader :status, :spec
  end
end
