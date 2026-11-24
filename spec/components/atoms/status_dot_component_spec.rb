require "rails_helper"

RSpec.describe Atoms::StatusDotComponent, type: :component do
  it "renders the live state by default" do
    render_inline(described_class.new)
    expect(page).to have_css("span.bg-live")
    expect(page).to have_text("[live]")
  end

  it "renders known states with their label and color" do
    render_inline(described_class.new(state: :crashed))
    expect(page).to have_css("span.bg-danger")
    expect(page).to have_text("[crashed]")
  end

  it "omits the label for :ok" do
    render_inline(described_class.new(state: :ok))
    expect(page).to have_css("span.bg-live")
    expect(page).not_to have_css("span.font-mono")
  end

  it "falls back to live for unknown states and honors label override" do
    render_inline(described_class.new(state: :bogus, label: "custom"))
    expect(page).to have_css("span.bg-live")
    expect(page).to have_text("custom")
  end
end

RSpec.describe Atoms::StatusDotComponent, "status light mapping", type: :component do
  { building: "wk-blink-1s", live: "bg-live", ok: "bg-live" }.each do |state, cls|
    it "maps #{state} through StatusLight (#{cls})" do
      render_inline(described_class.new(state: state))
      expect(page).to have_css("span.#{cls}")
    end
  end
end
