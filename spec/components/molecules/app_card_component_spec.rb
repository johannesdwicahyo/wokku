require "rails_helper"

RSpec.describe Molecules::AppCardComponent, type: :component do
  it "renders name, domain, region/tier and status dot" do
    render_inline(described_class.new(name: "warung", updated: "2m ago", domain: "warung.wokku.app"))
    expect(page).to have_text("warung")
    expect(page).to have_text("warung.wokku.app")
    expect(page).to have_text("region: jkt-1")
    expect(page).to have_text("tier: basic")
    expect(page).to have_text("updated 2m ago")
    expect(page).to have_text("[live]")
  end

  it "renders a non-default status and overrides" do
    render_inline(described_class.new(name: "x", status: :crashed, updated: "now", domain: "x.app", region: "sg-1", container: "pro"))
    expect(page).to have_text("[crashed]")
    expect(page).to have_text("region: sg-1")
    expect(page).to have_text("tier: pro")
  end
end
