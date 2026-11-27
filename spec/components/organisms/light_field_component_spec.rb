# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::LightFieldComponent, type: :component do
  it "renders an accessible canvas wired to the controller with a poster fallback" do
    render_inline(described_class.new(label: "A field of server lights"))
    canvas = page.find("canvas")
    expect(canvas[:role]).to eq("img")
    expect(canvas[:"aria-label"]).to eq("A field of server lights")
    expect(canvas[:"data-controller"]).to eq("light-field")
    expect(canvas[:class]).to include("wk-light-poster")
    expect(canvas[:"data-light-field-density-value"]).to eq("normal")
    expect(canvas[:"data-light-field-logo-value"]).to eq("true")
  end

  it "passes density and logo through as values" do
    render_inline(described_class.new(label: "x", logo: false, density: :low))
    canvas = page.find("canvas")
    expect(canvas[:"data-light-field-density-value"]).to eq("low")
    expect(canvas[:"data-light-field-logo-value"]).to eq("false")
  end

  it "rejects unknown densities" do
    expect { described_class.new(label: "x", density: :huge) }.to raise_error(ArgumentError)
  end
end
