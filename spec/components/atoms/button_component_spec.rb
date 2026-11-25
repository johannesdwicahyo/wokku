require "rails_helper"

RSpec.describe Atoms::ButtonComponent, type: :component do
  it "turns method: on a link into Turbo's data-turbo-method (a bare method attribute sends GET)" do
    render_inline(described_class.new(href: "/dashboard/invoices/1/pay", method: :post)) { "pay" }
    link = page.find("a", text: "pay")
    expect(link["data-turbo-method"]).to eq("post")
    expect(link["method"]).to be_nil
  end

  it "renders a plain link without a method and a button without an href" do
    render_inline(described_class.new(href: "/x")) { "go" }
    expect(page.find("a", text: "go")["data-turbo-method"]).to be_nil
    render_inline(described_class.new(type: "submit")) { "save" }
    expect(page).to have_css("button[type='submit']", text: "save")
  end
end

RSpec.describe Atoms::ButtonComponent, "control-room variants", type: :component do
  it "primary has the live fill and the square glyph" do
    render_inline(described_class.new(variant: :primary)) { "Deploy" }
    expect(page).to have_css("button.bg-live.text-\\[\\#03140A\\]")
    expect(page).to have_css("button span.wk-glyph[aria-hidden='true']")
    expect(page).to have_css("button.min-h-\\[38px\\].uppercase")
  end

  it "secondary, ghost and danger render without the glyph; old names alias" do
    render_inline(described_class.new(variant: :secondary)) { "x" }
    expect(page).to have_css("button.border-line-strong")
    expect(page).not_to have_css(".wk-glyph")
    render_inline(described_class.new(variant: :danger)) { "x" }
    expect(page).to have_css("button.border-danger.text-bad-text")
    render_inline(described_class.new(variant: :outline)) { "x" }
    expect(page).to have_css("button.border-line-strong")
  end
end
