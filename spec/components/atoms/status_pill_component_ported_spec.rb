require "rails_helper"

RSpec.describe Atoms::StatusPillComponent, type: :component do
  it "renders running with the CSS pulse animation" do
    # Redesigned engine drives the running-pill pulse via a pure-CSS
    # animation utility (animate-[wk-pulse_…]) instead of the old
    # motion--status-pulse Stimulus controller.
    render_inline(described_class.new(status: "running"))
    expect(page).to have_css('span[class*="wk-pulse"]')
  end

  it "falls back to stopped for unknown status" do
    render_inline(described_class.new(status: "bogus"))
    expect(page).to have_text(/stopped/i)
  end
end
