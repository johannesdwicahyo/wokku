module Atoms
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      primary:         "bg-ink text-bg",
      outline:         "bg-transparent text-ink",
      inverse:         "bg-bg text-ink",
      inverse_outline: "bg-transparent text-bg border-bg",
      ghost:           "bg-transparent text-ink-soft hover:text-ink",
      danger:          "bg-transparent text-danger"
    }.freeze

    SIZES = {
      sm: "px-3.5 py-2 text-xs",
      md: "px-5 py-3 text-sm",
      lg: "px-7 py-4 text-base"
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
      base = "inline-flex items-center justify-center gap-2 font-semibold tracking-tight cursor-pointer border-1.5 border-ink rounded-lg transition-all active:translate-y-px"
      shadow = %i[primary inverse inverse_outline].include?(@variant) ? "shadow-brutal-sm hover:shadow-brutal" : ""
      font = @mono ? "font-mono font-normal tracking-normal" : ""
      cx(base, VARIANTS[@variant], SIZES[@size], shadow, font, @opts[:class])
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
