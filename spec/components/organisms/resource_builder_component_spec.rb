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
    %w[Nano Starter Standard Large X-Large].each { |n| expect(page).to have_button(n) }
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
    expect(page).to have_css("[data-resource-builder-target='price']", text: "Rp32,000")
  end

  it "offers the free sleeping option and disk with a floor" do
    allow(Wokku).to receive(:cloud?).and_return(true) # "(free)" is cloud copy
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

  describe "upcoming price change" do
    let(:units) { { "cpu" => 16_000, "memory_gb" => 24_000, "disk_gb" => 1_000 } }

    it "renders nothing with the null provider (OSS)" do
      expect(Wokku::Providers::NullPricing.new.upcoming_change).to be_nil
      render_inline(described_class.new(name: "p", shape: shape, presets: {}))
      expect(page).to have_no_css("[data-test='price-change']")
    end

    it "renders nothing when a provider lacks the method or has no change" do
      allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 32_000))
      render_inline(described_class.new(name: "p", shape: shape, presets: {}))
      expect(page).to have_no_css("[data-test='price-change']")

      allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 32_000, upcoming_change: nil))
      render_inline(described_class.new(name: "p", shape: shape, presets: {}))
      expect(page).to have_no_css("[data-test='price-change']")
    end

    it "shows the date and the changed unit prices near the total" do
      change = { effective_on: Date.new(2026, 11, 4), from: units, to: units.merge("cpu" => 20_000) }
      allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 32_000, upcoming_change: change))
      render_inline(described_class.new(name: "p", shape: shape, presets: {}))
      note = page.find("[data-test='price-change']")
      expect(note.text).to include("4 Nov 2026", "vCPU Rp16,000 → Rp20,000")
      expect(note.text).not_to include("RAM")
    end
  end

  # Self-host never sleeps apps (IdleCheckJob is cloud-only), so the 256 MB
  # size is "Tiny" there; the Rails hint only applies to that size.
  it "names the 256 MB size Tiny on self-host and ties the Rails hint to it" do
    render_inline(described_class.new(name: "p", shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512, disk_gb: 10), presets: {}, sleeping_option: true, rails_hint: true))
    expect(page).to have_button("Tiny")
    expect(page).not_to have_button(/Sleeping/)
    expect(page).to have_css("[data-resource-builder-target='railsHint'].hidden", visible: :all)
  end

  describe "pricing kind" do
    after { Wokku.config.pricing = nil }

    let(:kind_provider) do
      Class.new do
        attr_reader :calls
        def initialize = @calls = []
        def unit_prices(kind: :app) = (@calls << [ :unit_prices, kind ]; { "cpu" => 1, "memory_gb" => 1, "disk_gb" => 1 })
        def monthly_idr(_shape, instances: 1, kind: :app) = (@calls << [ :monthly_idr, kind ]; 100)
        def upcoming_change(kind: :app) = (@calls << [ :upcoming_change, kind ]; nil)
      end.new
    end

    it "passes kind: :database through to every seam call" do
      Wokku.config.pricing = kind_provider
      render_inline(described_class.new(name: "", shape: shape, presets: {}, kind: :database))
      expect(kind_provider.calls).to include([ :unit_prices, :database ], [ :monthly_idr, :database ], [ :upcoming_change, :database ])
    end

    it "does not pass kind for apps (default)" do
      Wokku.config.pricing = kind_provider
      render_inline(described_class.new(name: "p", shape: shape, presets: {}))
      expect(kind_provider.calls.map(&:last).uniq).to eq([ :app ])
    end

    it "keeps working with a provider that predates kind:" do
      old = Class.new do
        def unit_prices = { "cpu" => 1, "memory_gb" => 1, "disk_gb" => 1 }
        def monthly_idr(_shape, instances: 1) = 50
        def upcoming_change = nil
      end.new
      Wokku.config.pricing = old
      render_inline(described_class.new(name: "", shape: shape, presets: {}, kind: :database))
      expect(page).to have_css("[data-resource-builder-target='price']", text: "Rp50")
    end

    it "is unaffected on the default (null) provider" do
      render_inline(described_class.new(name: "", shape: shape, presets: {}, kind: :database))
      expect(page).to have_no_css("[data-resource-builder-target='price']")
    end
  end
end
