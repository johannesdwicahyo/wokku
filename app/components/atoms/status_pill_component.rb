module Atoms
  # Status badge, schdl idiom: paper pill with ink border and a colored
  # status dot. Color is never the only indicator — the label always shows.
  class StatusPillComponent < ApplicationComponent
    STATUSES = {
      "running"   => { label: "Running",   dot: "var(--color-success)" },
      "deploying" => { label: "Deploying", dot: "var(--color-deploying)" },
      "crashed"   => { label: "Crashed",   dot: "var(--color-danger)" },
      "stopped"   => { label: "Stopped",   dot: "var(--color-dim)" },
      "sleeping"  => { label: "Sleeping",  dot: "var(--color-warn)" }
    }.freeze

    def initialize(status:)
      @status = status.to_s
      @spec   = STATUSES.fetch(@status, STATUSES["stopped"])
    end
    attr_reader :status, :spec
  end
end
