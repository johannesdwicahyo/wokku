require "rails_helper"

RSpec.describe Organisms::AppsOverviewComponent, type: :component do
  let(:fleet) { [ { app_id: 1, name: "a", states: %i[running deploying] } ] }
  let(:args) { { fleet: fleet, running: 5, total: 6, deploying: 1 } }

  it "renders the board cell and the Running readout with deploying sub" do
    render_inline(described_class.new(**args))
    expect(page).to have_css("section[aria-label='Overview']")
    expect(page).to have_text("Fleet · per process")
    expect(page).to have_css("canvas[data-controller='light-board']")
    expect(page).to have_text("Running")
    expect(page.text).to include("5").and include("/ 6")
    expect(page).to have_text("1 deploying")
  end

  it "omits the deploying sub when none are deploying" do
    render_inline(described_class.new(**args, deploying: 0))
    expect(page).not_to have_css("[data-sub]")
  end

  it "renders seam readouts in order after Running, and no Rp without them" do
    render_inline(described_class.new(**args))
    expect(page.text).not_to include("Rp")
    render_inline(described_class.new(**args, readouts: [ { label: "This month", value: "Rp1", sub: "so far" }, { label: "Next", value: "Rp2" } ]))
    expect(page.text.scan(/Running|This month|Next\b/)).to eq([ "Running", "This month", "Next" ])
    expect(page).to have_text("so far")
  end

  it "localizes under :id" do
    I18n.with_locale(:id) do
      render_inline(described_class.new(**args))
      expect(page).to have_text("Armada · per proses")
      expect(page).to have_text("Berjalan")
      expect(page).to have_text("1 sedang deploy")
    end
  end

  describe ".readouts_for" do
    after { Wokku.config.apps_index_readouts = nil }

    it "defaults to none" do
      expect(Wokku.config.apps_index_readouts.call(nil, nil)).to eq([])
      expect(described_class.readouts_for(nil, nil)).to eq([])
    end

    it "filters malformed entries" do
      Wokku.config.apps_index_readouts = ->(_v, _t) { [ { label: "A", value: "1" }, "x", { label: "B" }, { value: "2" } ] }
      expect(described_class.readouts_for(nil, nil)).to eq([ { label: "A", value: "1" } ])
    end

    it "returns [] and reports when the seam raises or returns a non-array" do
      Wokku.config.apps_index_readouts = ->(_v, _t) { raise "boom" }
      expect(Rails.logger).to receive(:error).with(/boom/)
      expect(described_class.readouts_for(nil, nil)).to eq([])
      Wokku.config.apps_index_readouts = ->(_v, _t) { nil }
      expect(described_class.readouts_for(nil, nil)).to eq([])
    end
  end
end
