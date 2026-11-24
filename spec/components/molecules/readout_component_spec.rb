require "rails_helper"

RSpec.describe Molecules::ReadoutComponent, type: :component do
  it "renders label, value and sub" do
    render_inline(described_class.new(label: "Apps", value: "12", sub: "3 sleeping"))
    expect(page).to have_text("Apps")
    expect(page).to have_css(".text-\\[30px\\]", text: "12")
    expect(page).to have_text("3 sleeping")
  end

  it "omits sub and supports the live tone" do
    render_inline(described_class.new(label: "Up", value: "9", tone: :live))
    expect(page).to have_css(".text-live", text: "9")
    expect(page).not_to have_css("[data-sub]")
  end
end
