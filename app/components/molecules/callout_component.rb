module Molecules
  # Docs callout (`:::callout <tone>`). Each tone is one colour token: the
  # square light, the label and a faint border/tint (docs.css .doc-callout).
  class CalloutComponent < ApplicationComponent
    TONES = {
      note:    { color: "--color-muted",   default_eyebrow: "Note" },
      warn:    { color: "--color-warn",    default_eyebrow: "Careful" },
      success: { color: "--color-success", default_eyebrow: "Tip" },
      danger:  { color: "--color-danger",  default_eyebrow: "Danger" }
    }.freeze

    def initialize(tone: :note, eyebrow: nil)
      @tone    = tone
      @config  = TONES.fetch(tone)
      @eyebrow = eyebrow || @config[:default_eyebrow]
    end
    attr_reader :tone, :eyebrow

    def style = "--callout: var(#{@config[:color]});"
  end
end
