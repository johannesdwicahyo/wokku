# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::SidebarNavItemComponent, type: :component do
  it "renders label and a mono count, never an svg" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/dashboard/apps", count: 3))
    expect(page).to have_link("Apps", href: "/dashboard/apps")
    expect(page).to have_css("span.font-mono", text: "3")
    expect(page).not_to have_css("svg")
  end

  it "ignores icon: so the legacy sidebar keeps rendering" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/x", icon: "apps"))
    expect(page).not_to have_css("svg")
  end

  it "marks the active item with aria-current and a live border" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/x", active: true))
    link = page.find("a")
    expect(link[:"aria-current"]).to eq("page")
    expect(link[:class]).to include("border-live")
  end

  it "leaves inactive items with a transparent border and no aria-current" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/x"))
    link = page.find("a")
    expect(link[:"aria-current"]).to be_nil
    expect(link[:class]).to include("border-transparent")
  end
end
