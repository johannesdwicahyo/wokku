require "rails_helper"

RSpec.describe Molecules::DashedCalloutComponent, type: :component do
  it "renders content with ink tone and empty style by default" do
    render_inline(described_class.new) { "note" }
    expect(page).to have_css("div.border-line.text-ink", text: "note")
    expect(page.find("div")[:style]).to eq("")
  end

  it "renders accent tone with width and position styles" do
    render_inline(described_class.new(tone: :accent, width: 180, position: { top: 10, left: 20 })) { "hey" }
    div = page.find("div")
    expect(div[:class]).to include("border-line", "text-accent")
    expect(div[:style]).to eq("width: 180px; top: 10px; left: 20px")
  end
end
