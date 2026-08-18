module Atoms
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      primary:         "bg-ink text-paper border border-ink hover:opacity-90",
      outline:         "bg-paper text-ink border border-line hover:bg-bg",
      inverse:         "bg-paper text-ink border border-line hover:bg-bg",
      inverse_outline: "bg-transparent text-paper border border-paper/40 hover:border-paper",
      ghost:           "bg-transparent text-ink-soft border border-transparent hover:text-ink hover:bg-bg",
      danger:          "bg-transparent text-danger border border-line hover:bg-danger-soft"
    }.freeze

    SIZES = {
      sm: "px-3 py-1.5 text-xs",
      md: "px-4 py-2 text-sm",
      lg: "px-5 py-2.5 text-base"
    }.freeze

    def initialize(variant: :primary, size: :md, href: nil, type: "button", mono: false, **opts)
      @variant = variant
      @size = size
      @href = href
      @type = type
      @mono = mono
      @opts = opts
    end

    def classes
      base = "inline-flex items-center justify-center gap-2 font-medium cursor-pointer rounded-md transition-colors"
      font = @mono ? "font-mono font-normal" : ""
      cx(base, VARIANTS[@variant], SIZES[@size], font, @opts[:class])
    end

    def tag_name
      @href ? :a : :button
    end

    def attrs
      a = { class: classes }
      a[:href] = @href if @href
      a[:type] = @type unless @href
      a.merge(@opts.except(:class))
    end
  end
end
