require "rails_helper"

RSpec.describe EngineSmokeComponent, type: :component do
  it "renders the unique marker class" do
    render_inline(described_class.new)
    expect(page).to have_css(".wokku-engine-smoke-marker")
  end
end
