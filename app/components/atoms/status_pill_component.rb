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

    TONES = {
      success:   "var(--color-success)",
      info:      "var(--color-info)",
      danger:    "var(--color-danger)",
      warn:      "var(--color-warn)",
      deploying: "var(--color-deploying)",
      neutral:   "var(--color-dim)"
    }.freeze

    def initialize(status: nil, label: nil, tone: nil)
      if label
        @status = label.to_s.downcase
        @spec   = { label: label, dot: TONES.fetch(tone || :neutral) }
      else
        @status = status.to_s
        @spec   = STATUSES.fetch(@status, STATUSES["stopped"])
      end
    end
    attr_reader :status, :spec
  end
end
