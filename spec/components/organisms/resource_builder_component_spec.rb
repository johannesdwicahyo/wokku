# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::ResourceBuilderComponent, type: :component do
  let(:shape) { Resources::Shape.new(cpu: 0.5, memory_mb: 1024) }

  it "renders grid-bounded sliders named under the prefix" do
    render_inline(described_class.new(name: "processes[web]", shape: shape, presets: Resources::Shape::PRESETS, instances: 1))
    cpu = page.find("input[name='processes[web][cpu]']")
    expect(cpu[:type]).to eq("range")
    expect(cpu[:min]).to eq("0.25")
    expect(cpu[:max]).to eq("4.0")
    expect(cpu[:step]).to eq("0.25")
    expect(cpu[:value]).to eq("0.5")
    expect(page).to have_css("input[name='processes[web][memory_mb]'][step='256'][min='256'][max='8192']")
    expect(page).to have_css("input[name='processes[web][count]']")
    expect(page).to have_no_css("input[name='processes[web][disk_gb]']")
  end

  it "renders preset chips with the Rails hint on 256MB presets" do
    render_inline(described_class.new(name: "p", shape: shape, presets: Resources::Shape::PRESETS, rails_hint: true))
    %w[Nano Starter Standard Pro Big].each { |n| expect(page).to have_button(n) }
    expect(page).to have_text("not enough for Rails")
  end

  it "shows no price line when pricing is null (OSS)" do
    render_inline(described_class.new(name: "p", shape: shape, presets: {}))
    expect(page).to have_no_css("[data-resource-builder-target='price']")
  end

  it "passes unit prices to the controller when pricing is injected" do
    pricing = double(unit_prices: { "cpu" => 16_000, "memory_gb" => 24_000, "disk_gb" => 1_000 }, monthly_idr: 32_000)
    allow(Wokku.config).to receive(:pricing).and_return(pricing)
    render_inline(described_class.new(name: "p", shape: shape, presets: {}))
    root = page.find("[data-controller='resource-builder']")
    expect(JSON.parse(root["data-resource-builder-units-value"])).to eq("cpu" => 16_000, "memory_gb" => 24_000, "disk_gb" => 1_000)
    expect(page).to have_css("[data-resource-builder-target='price']", text: "Rp32.000")
  end

  it "offers the free sleeping option and disk with a floor" do
    render_inline(described_class.new(name: "p", shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512, disk_gb: 10), presets: {}, disk: true, min_disk_gb: 10, sleeping_option: true))
    expect(page).to have_button("Sleeping (free)")
    expect(page).to have_css("input[name='p[disk_gb]'][min='10']")
  end

  it "only marks a datastore preset chip pressed when disk also matches" do
    small = Resources::Shape::SERVICE_PRESETS["postgres"]["small"]

    render_inline(described_class.new(
      name: "p",
      shape: Resources::Shape.new(cpu: small[:cpu], memory_mb: small[:memory_mb], disk_gb: small[:disk_gb]),
      presets: Resources::Shape::SERVICE_PRESETS["postgres"], disk: true
    ))
    expect(page).to have_css("button[aria-pressed='true']", text: "Small")

    render_inline(described_class.new(
      name: "p",
      shape: Resources::Shape.new(cpu: small[:cpu], memory_mb: small[:memory_mb], disk_gb: 10),
      presets: Resources::Shape::SERVICE_PRESETS["postgres"], disk: true
    ))
    expect(page).to have_css("button[aria-pressed='false']", text: "Small")
  end
end
