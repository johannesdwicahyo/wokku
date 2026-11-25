require "rails_helper"

RSpec.describe Atoms::LightBarsComponent, type: :component do
  it "renders one bar per value, scaled to max, lit only when > 0" do
    render_inline(described_class.new(values: [ 50, 0, nil ] + Array.new(9, 100), label: "CPU 1 h"))
    bars = page.find("[role='img']")
    expect(bars["aria-label"]).to eq("CPU 1 h")
    expect(bars.all("i").size).to eq(12)
    expect(bars.all("i")[0]["style"]).to include("9px")
    expect(bars.all("i")[1]["class"]).not_to include("on")
    expect(bars.all("i")[1]["style"]).to include("2px")
    expect(bars.all("i.on").size).to eq(10)
  end

  it "clamps values above max to the full row height" do
    render_inline(described_class.new(values: [ 250 ], label: "CPU"))
    expect(page.find("i")["style"]).to include("height: 18px")
  end

  it "renders a labelled dash when there is no data" do
    [ [], [ nil, nil ] ].each do |vals|
      render_inline(described_class.new(values: vals, label: "CPU"))
      expect(page).to have_css("[aria-label='No CPU data yet']", text: "—")
      expect(page).not_to have_css("i")
    end
  end

  it "labels the empty state in Indonesian" do
    I18n.with_locale(:id) { render_inline(described_class.new(values: [], label: "CPU")) }
    expect(page).to have_css("[aria-label='Belum ada data CPU']")
  end
end
