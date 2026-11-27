# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::LightWallComponent, type: :component do
  it "renders a decorative canvas wired to the light-wall controller" do
    render_inline(described_class.new(label: "Closing wall"))
    canvas = page.find("canvas")
    expect(canvas[:"aria-hidden"]).to eq("true")
    expect(canvas[:role]).to be_nil
    expect(canvas[:"data-controller"]).to eq("light-wall")
    expect(canvas[:"data-light-wall-text-value"]).to eq("PUSH.")
  end
end
