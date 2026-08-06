module Molecules
  class TerminalComponent < ApplicationComponent
    DEFAULT_SCRIPT = [
      { kind: "cmd", text: "$ wokku deploy warung-app" },
      { kind: "out", segs: [ [ "→ building... ", "dim" ], [ "[buildpacks/nodejs]", "accent" ] ] },
      { kind: "out", segs: [ [ "→ pushing to jkt-1... ", "dim" ], [ "✓", "hot" ] ] },
      { kind: "out", segs: [ [ "✓ live ", "hot" ], [ "(28.4s)", "dim" ] ] },
      { kind: "out", segs: [ [ "↗ warung-app.wokku.app", "accent" ] ], delay: 400 }
    ].freeze

    def initialize(title: "~/proyek — wokku", script: nil, width: nil, rotate: nil, with_elapsed: false)
      @title = title
      @script = script || DEFAULT_SCRIPT
      @width = width
      @rotate = rotate
      @with_elapsed = with_elapsed
    end

    attr_reader :title, :with_elapsed

    def container_style
      parts = []
      parts << "width: #{@width}px" if @width
      parts << "transform: rotate(#{@rotate}deg)" if @rotate
      parts.join("; ")
    end

    def script_json
      @script.to_json
    end

    # Render every script line as invisible HTML so the <pre> occupies its
    # full final height from frame 0 (ghost layer, color:transparent).
    # The JS animation overlays this with position:absolute, so it never
    # causes reflow as lines type in. The trailing cursor line is included
    # so the ghost accounts for the "$ _" line the controller appends at
    # the end of each loop.
    def ghost_lines_html
      lines = @script.map do |line|
        case line[:kind]
        when "cmd"
          "<div>#{ERB::Util.html_escape(line[:text] || "")}</div>"
        when "out"
          segs = (line[:segs] || []).map { |text, _tone| ERB::Util.html_escape(text) }.join
          "<div>#{segs}</div>"
        else
          "<div>&nbsp;</div>"
        end
      end
      # Trailing cursor line the controller adds when animation completes
      lines << "<div>$ _</div>"
      lines.join.html_safe
    end
  end
end
