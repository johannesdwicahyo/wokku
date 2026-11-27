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

  it "renders text mode as an img canvas with the name in a text value" do
    render_inline(described_class.new(mode: :text, data: "my-app.1", label: "App name preview: my-app.1"))
    canvas = page.find("canvas[data-controller='light-board']")
    expect(canvas["data-light-board-mode-value"]).to eq("text")
    expect(canvas["data-light-board-text-value"]).to eq("my-app.1")
    expect(canvas["role"]).to eq("img")
    expect(canvas["aria-label"]).to eq("App name preview: my-app.1")
    expect(canvas["aria-hidden"]).to be_nil
  end

  it "renders story mode: controller wrapper, decorative canvas target, caption targets, sr-only label" do
    render_inline(described_class.new(mode: :story, label: "Push, build, live",
      data: { steps: %w[PUSH BUILD LIVE], status_labels: { live: "aktif" }, repo: "toko · main@abc" }))
    root = page.find("div[data-controller='light-board']")
    expect(root["data-light-board-mode-value"]).to eq("story")
    story = JSON.parse(root["data-light-board-story-value"])
    expect(story["steps"]).to eq(%w[PUSH BUILD LIVE])
    expect(story["status_labels"]["live"]).to eq("aktif")
    expect(page).to have_css("canvas[aria-hidden='true'][data-light-board-target='canvas']")
    expect(page).to have_css("[data-light-board-target='left']", text: "toko · main@abc")
    expect(page).to have_css("[data-light-board-target='right']", text: "aktif")
    expect(page).to have_css("span.sr-only", text: "Push, build, live")
  end

  it "defaults story data to English" do
    render_inline(described_class.new(mode: :story, label: "x"))
    story = JSON.parse(page.find("div[data-controller='light-board']")["data-light-board-story-value"])
    expect(story["steps"]).to eq(%w[PUSH BUILD LIVE])
  end

  it "rejects an unknown mode" do
    expect { described_class.new(mode: :bogus, data: [], label: "x") }.to raise_error(ArgumentError)
  end
end
