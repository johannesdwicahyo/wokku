# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::SidebarNavItemComponent, type: :component do
  it "renders label, icon and count" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/dashboard/apps", icon: "apps", count: 3))
    expect(page).to have_link("Apps", href: "/dashboard/apps")
    expect(page).to have_css("a svg")
    expect(page).to have_css("span.text-dim", text: "3")
  end

  it "renders without icon or count" do
    render_inline(described_class.new(label: "Team", key: :team, href: "/x"))
    expect(page).to have_link("Team", href: "/x")
    expect(page).not_to have_css("a svg")
  end

  it "marks the active item with the hover-surface style and no marker glyph" do
    render_inline(described_class.new(label: "Apps", key: :apps, href: "/x", active: true, icon: "apps"))
    link = page.find("a")
    expect(link[:class]).to include("bg-bg-deep")
    expect(link[:class]).to include("font-semibold")
    expect(page).not_to have_text(">")
  end
end
