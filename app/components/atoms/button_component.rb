module Atoms
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      primary:         "bg-ink text-paper border-1.5 border-ink shadow-brutal hover:bg-ink/90",
      outline:         "bg-paper text-ink border-1.5 border-ink shadow-brutal-sm hover:bg-bg-deep",
      inverse:         "bg-paper text-ink border-1.5 border-ink shadow-brutal-sm hover:bg-bg-deep",
      inverse_outline: "bg-transparent text-paper border-1.5 border-paper/40 hover:border-paper",
      ghost:           "bg-transparent text-ink-soft border-1.5 border-transparent hover:text-ink hover:bg-bg-deep",
      danger:          "bg-paper text-danger border-1.5 border-danger shadow-brutal-sm hover:bg-danger-soft"
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
      # A link can't send POST/DELETE on its own: `method:` becomes Turbo's
      # data-turbo-method (a bare method="post" attribute was ignored -> GET 404).
      @method = opts.delete(:method)
      @opts = opts
    end

    def classes
      base = "inline-flex items-center justify-center gap-2 font-semibold cursor-pointer rounded-md transition-[transform,box-shadow,background-color] duration-75 active:translate-x-[2px] active:translate-y-[2px] active:shadow-none"
      font = @mono ? "font-mono font-normal" : ""
      cx(base, VARIANTS[@variant], SIZES[@size], font, @opts[:class])
    end

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
