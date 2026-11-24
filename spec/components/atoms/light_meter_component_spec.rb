require "rails_helper"

RSpec.describe Atoms::LightMeterComponent, type: :component do
  it "renders total squares with the first `on` lit" do
    render_inline(described_class.new(total: 10, on: 4, label: "CPU"))
    meter = page.find("[role='meter']")
    expect(meter["aria-valuenow"]).to eq("4")
    expect(meter["aria-valuemax"]).to eq("10")
    expect(meter["aria-label"]).to eq("CPU")
    expect(meter.all("span").size).to eq(10)
    expect(meter.all("span.on").size).to eq(4)
  end

  it "uses the live tone" do
    render_inline(described_class.new(total: 3, on: 1, tone: :live, label: "x"))
    expect(page).to have_css("span.on.bg-live")
  end
end
