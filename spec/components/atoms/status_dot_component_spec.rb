require "rails_helper"

RSpec.describe Atoms::StatusDotComponent, type: :component do
  it "renders the live state by default" do
    render_inline(described_class.new)
    expect(page).to have_css("span.bg-success")
    expect(page).to have_text("[live]")
  end

  it "renders known states with their label and color" do
    render_inline(described_class.new(state: :crashed))
    expect(page).to have_css("span.bg-danger")
    expect(page).to have_text("[crashed]")
  end

  it "omits the label for :ok" do
    render_inline(described_class.new(state: :ok))
    expect(page).to have_css("span.bg-success")
    expect(page).not_to have_css("span.font-mono")
  end

  it "falls back to live for unknown states and honors label override" do
    render_inline(described_class.new(state: :bogus, label: "custom"))
    expect(page).to have_css("span.bg-success")
    expect(page).to have_text("custom")
  end
end
