module Molecules
  # Docs callout (`:::callout <tone>`). Each tone is one colour token: the
  # square light, the label and a faint border/tint (docs.css .doc-callout).
  class CalloutComponent < ApplicationComponent
    TONES = {
      note:    { color: "--color-muted" },
      warn:    { color: "--color-warn" },
      success: { color: "--color-success" },
      danger:  { color: "--color-danger" }
    }.freeze

    def initialize(tone: :note, eyebrow: nil)
      @tone    = tone
      @config  = TONES.fetch(tone)
      @eyebrow = eyebrow || I18n.t("docs.callout.#{tone}")
    end
    attr_reader :tone, :eyebrow

    def style = "--callout: var(#{@config[:color]});"
  end
end
