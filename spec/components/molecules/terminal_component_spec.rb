require "rails_helper"

RSpec.describe Molecules::TerminalComponent, type: :component do
  it "renders defaults: title, default script json, no inline style, no elapsed badge" do
    render_inline(described_class.new)
    expect(page).to have_text("~/proyek — wokku")
    expect(page).to have_css('[data-controller="hero-terminal"]')
    expect(page).to have_css('[data-hero-terminal-script-value*="warung-app"]')
    expect(page).not_to have_css('[data-hero-terminal-target="elapsed"]')
    # ghost layer includes cmd text, out segs, and trailing cursor line
    expect(page).to have_text("$ wokku deploy warung-app")
    expect(page).to have_text("$ _")
  end

  it "applies width and rotate to container style and shows elapsed badge" do
    render_inline(described_class.new(width: 420, rotate: -2, with_elapsed: true))
    expect(page).to have_css('[style*="width: 420px"]')
    expect(page).to have_css('[style*="rotate(-2deg)"]')
    expect(page).to have_css('[data-hero-terminal-target="elapsed"]', text: "0.0s")
  end

  it "renders custom scripts, escaping cmd text and handling unknown kinds" do
    script = [
      { kind: "cmd", text: "$ echo <hi>" },
      { kind: "out", segs: [ [ "done <ok>", "dim" ] ] },
      { kind: "gap" }
    ]
    render_inline(described_class.new(title: "custom", script: script))
    expect(page).to have_text("custom")
    expect(page).to have_text("$ echo <hi>")
    expect(page).to have_text("done <ok>")
    ghost = page.find("pre[aria-hidden='true']")
    expect(ghost.native.inner_html).to include("&lt;hi&gt;")
    expect(ghost.native.inner_html).to include("\u00A0") # unknown kind renders an &nbsp; placeholder line
  end

  it "tolerates cmd lines without text and out lines without segs" do
    render_inline(described_class.new(script: [ { kind: "cmd" }, { kind: "out" } ]))
    expect(page).to have_css("pre[aria-hidden='true']")
  end
end
