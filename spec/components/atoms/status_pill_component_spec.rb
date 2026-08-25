require "rails_helper"

RSpec.describe Atoms::StatusPillComponent, type: :component do
  it "renders the outline-dot badge for running" do
    render_inline(described_class.new(status: "running"))
    expect(page).to have_text("Running")
    expect(page).to have_css("span.border-ink.rounded-full")
    expect(page).to have_css("span[style*='--color-success']")
  end

  it "falls back to the stopped style for unknown statuses" do
    render_inline(described_class.new(status: "weird"))
    expect(page).to have_text("Stopped")
    expect(page).to have_css("span[style*='--color-dim']")
  end
end
