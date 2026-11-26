require "rails_helper"

RSpec.describe Organisms::LightBoardComponent, type: :component do
  let(:fleet) { [ { app_id: 1, name: "a", states: %i[running deploying] } ] }
  let(:label) { described_class.fleet_label(Apps::Fleet.counts(fleet)) }

  it "renders a decorative canvas with controller, mode and JSON data, plus an sr-only summary" do
    render_inline(described_class.new(mode: :fleet, data: fleet, label: label))
    canvas = page.find("canvas[data-controller='light-board']")
    expect(canvas["aria-hidden"]).to eq("true")
    expect(canvas["data-light-board-mode-value"]).to eq("fleet")
    expect(JSON.parse(canvas["data-light-board-data-value"]).first["states"]).to eq(%w[running deploying])
    expect(page).to have_css("span.sr-only", text: "2 processes: 1 running, 1 deploying")
  end

  it "summarises in Indonesian under :id" do
    I18n.with_locale(:id) do
      expect(described_class.fleet_label(running: 5, deploying: 1)).to eq("6 proses: 5 berjalan, 1 deploy")
    end
  end

  it "is empty for an empty fleet" do
    expect(described_class.fleet_label({})).to eq("")
  end
end
