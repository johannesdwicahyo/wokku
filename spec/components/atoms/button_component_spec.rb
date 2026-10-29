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
