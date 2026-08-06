module Molecules
  class CalloutComponent < ApplicationComponent
    TONES = {
      note:    { border: "border-accent",  text: "text-accent",  bg: "bg-accent-soft",  default_eyebrow: "// note" },
      warn:    { border: "",               text: "",             bg: "bg-warn-soft",    default_eyebrow: "// careful",
                 var_border: "var(--color-warn)",   var_text: "var(--color-warn)" },
      success: { border: "border-success", text: "text-success", bg: "bg-success-soft", default_eyebrow: "// tip" },
      danger:  { border: "border-danger",  text: "text-danger",  bg: "bg-danger-soft",  default_eyebrow: "// danger" }
    }.freeze

    def initialize(tone: :note, eyebrow: nil)
      @config  = TONES.fetch(tone)
      @eyebrow = eyebrow || @config[:default_eyebrow]
    end

    def eyebrow; @eyebrow; end
    def border_class; "#{@config[:border]} #{@config[:bg]}"; end
    def text_class;   @config[:text]; end

    # Tones like :warn don't have a stable border token class — set via inline style.
    def style
      parts = []
      parts << "border-color: #{@config[:var_border]};" if @config[:var_border]
      parts << "color: #{@config[:var_text]};"          if @config[:var_text] && text_class.blank?
      parts.join(" ")
    end
  end
end
