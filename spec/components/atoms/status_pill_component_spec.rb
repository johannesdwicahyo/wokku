require "rails_helper"

RSpec.describe Atoms::StatusPillComponent, type: :component do
  it "renders running with pulse-enabled controller" do
    render_inline(described_class.new(status: "running"))
    expect(page).to have_css('[data-controller~="motion--status-pulse"]')
    expect(page).to have_css('[data-motion--status-pulse-status-value="running"]')
  end

  it "falls back to stopped for unknown status" do
    render_inline(described_class.new(status: "bogus"))
    expect(page).to have_text(/stopped/i)
  end
end
