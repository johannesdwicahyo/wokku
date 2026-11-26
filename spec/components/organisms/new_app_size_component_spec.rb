# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::NewAppSizeComponent, type: :component do
  let(:units) { { "cpu" => 24_000, "memory_gb" => 36_000, "disk_gb" => 1_000 } }

  before do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Wokku).to receive(:cloud?).and_return(true) # "Sleeping" is cloud copy; OSS says Tiny
  end

  def card(text) = page.find("label", text: text)

  it "renders the five preset cards with exact specs and the builder sliders" do
    render_inline(described_class.new)
    { "Sleeping" => "Sleeps when idle", "Nano" => "0.25 vCPU · 256 MB", "Basic" => "0.5 vCPU · 512 MB",
      "Standard" => "1 vCPU · 1 GB", "Large" => "2 vCPU · 2 GB" }.each do |name, spec|
      expect(card(name)).to have_text(spec)
    end
    expect(page).to have_css("input[type=radio][name=size_preset]", count: 5, visible: :all)
    expect(page).to have_css("input[name='processes[web][cpu]'][type=range]")
    expect(page).to have_checked_field("size_preset", with: "basic", visible: :all)
  end

  it "shows Rp only when pricing returns numbers" do
    render_inline(described_class.new)
    expect(page).to have_no_text("Rp")

    allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 30_000))
    render_inline(described_class.new)
    expect(card("Basic")).to have_text("Rp30,000")
    expect(JSON.parse(page.find("[data-new-app-target=size]")["data-units"])).to eq(units)
  end

  it "formats Rupiah the Indonesian way and translates" do
    allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 30_000))
    I18n.with_locale(:id) { render_inline(described_class.new) }
    expect(card("Basic")).to have_text("Rp30.000")
    expect(page).to have_text("Nama app")
    expect(card("Sleeping")).to have_text("Tidur saat tidak dipakai")
  end

  it "selects no card for a custom shape and re-renders the submitted name and sleeping choice" do
    render_inline(described_class.new(shape: Resources::Shape.new(cpu: 0.75, memory_mb: 768), name: "shop"))
    expect(page).to have_no_css("input[name=size_preset][checked]", visible: :all)
    expect(page).to have_field("app_record[name]", with: "shop")
    expect(page).to have_css("[data-new-app-target=customHint]:not(.hidden)")

    render_inline(described_class.new(sleeping: true))
    expect(page).to have_checked_field("size_preset", with: "sleeping", visible: :all)
  end

  it "labels the name status as a polite live region" do
    render_inline(described_class.new)
    expect(page).to have_css("#app_name_status[aria-live=polite]")
  end

  it "keeps the box-size grid on legacy installs" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(false)
    render_inline(described_class.new(box_quota: { "sleeping" => { provisionable: true }, "small" => { provisionable: false } }))
    expect(page).to have_css("input[name='app_record[box_size]'][value=sleeping]", visible: :all)
    expect(page).to have_css("button[data-box-size=small][disabled]")
    expect(page).to have_no_css("input[name=size_preset]", visible: :all)
  end

  it "exposes root data for the page controller" do
    data = described_class.root_data
    expect(data[:controller]).to eq("new-app app-name-check")
    expect(data[:new_app_delimiter_value]).to eq(",")
  end
end
