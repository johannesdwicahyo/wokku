module Atoms
  class ButtonComponent < ApplicationComponent
    SECONDARY = "bg-transparent text-ink border border-line-strong hover:border-ink"
    GHOST     = "bg-transparent text-ink-soft border border-transparent hover:text-ink"
    VARIANTS = {
      primary:         "bg-live text-[#03140A] border border-live hover:bg-live-hover hover:border-live-hover",
      secondary:       SECONDARY,
      ghost:           GHOST,
      danger:          "bg-transparent text-bad-text border border-danger hover:bg-danger-soft",
      # Legacy names kept for existing callers: outline/inverse -> secondary, inverse_outline -> ghost.
      outline:         SECONDARY,
      inverse:         SECONDARY,
      inverse_outline: GHOST
    }.freeze

    SIZES = {
      sm: "px-3",
      md: "px-4",
      lg: "px-5"
    }.freeze

    def initialize(variant: :primary, size: :md, href: nil, type: "button", mono: false, **opts)
      @variant = variant
      @size = size
      @href = href
      @type = type
      @mono = mono
      # A link can't send POST/DELETE on its own: `method:` becomes Turbo's
      # data-turbo-method (a bare method="post" attribute was ignored -> GET 404).
      @method = opts.delete(:method)
      @opts = opts
    end

    def classes
      base = "inline-flex items-center justify-center gap-2 min-h-[38px] font-mono text-[11px] font-medium uppercase tracking-[.1em] cursor-pointer transition-colors duration-75"
      cx(base, VARIANTS[@variant], SIZES[@size], @opts[:class])
    end

    def primary? = @variant == :primary

    def tag_name
      @href ? :a : :button
    end

    def attrs
      a = { class: classes }
      a[:href] = @href if @href
      a[:"data-turbo-method"] = @method.to_s if @href && @method && @method.to_s != "get"
      a[:type] = @type unless @href
      a.merge(@opts.except(:class))
    end
  end
end
