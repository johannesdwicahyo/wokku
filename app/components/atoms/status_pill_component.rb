module Atoms
  # Status pill with optional pulse animation when status=running.
  class StatusPillComponent < ApplicationComponent
    STATUSES = {
      "running"   => { label: "running",   color: "border-success bg-success-soft text-ink",   dot_color: "var(--color-success)" },
      "deploying" => { label: "deploying", color: "border-accent bg-accent-soft text-accent",  dot_color: "var(--color-accent)" },
      "crashed"   => { label: "crashed",   color: "border-danger bg-danger-soft text-danger",  dot_color: "var(--color-danger)" },
      "stopped"   => { label: "stopped",   color: "border-ink bg-bg-deep text-ink-soft",       dot_color: "var(--color-dim)" },
      "sleeping"  => { label: "sleeping",  color: "border-warn bg-warn-soft text-ink-soft",    dot_color: "var(--color-warn)" }
    }.freeze

    def initialize(status:)
      @status = status.to_s
      @spec   = STATUSES.fetch(@status, STATUSES["stopped"])
    end
    attr_reader :status, :spec
  end
end
