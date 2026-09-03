# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AppsTableComponent, type: :component do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:app) { create(:app_record, team: team, server: server, name: "alpha") }

  it "renders a row per app with name, status, and a link to the app" do
    render_inline(described_class.new(apps: [ app ]))

    expect(page).to have_css("table")
    expect(page).to have_link("alpha", href: "/dashboard/apps/#{app.id}")
    expect(page).to have_css("th", text: "Status")
  end

  it "renders each row as a focusable grid item with a status aria-label" do
    render_inline(described_class.new(apps: [ app ]))

    row = page.find("tr[data-grid-nav-target='row']")
    expect(row["tabindex"]).to eq("0")
    expect(row["role"]).to eq("button")
    expect(row["aria-label"]).to eq("alpha, Running")
  end

  it "renders an em dash when an app has no web dyno tier" do
    render_inline(described_class.new(apps: [ app ]))
    expect(page).to have_css("td", text: "—")
  end

  it "renders the inline new-app row and the avatar mark" do
    render_inline(described_class.new(apps: [ app ]))
    expect(page).to have_link("+ New app")
    expect(page).to have_css("span", text: app.name[0].upcase)
  end

  describe "#box_label" do
    # The SIZE column must show the box vocabulary (sleeping/small/medium/...),
    # not the raw internal DynoTier name (free/basic/standard/...).
    {
      "free" => "sleeping", "basic" => "small", "standard" => "medium",
      "performance" => "large", "performance-2x" => "xlarge"
    }.each do |tier_name, box_label|
      it "maps the #{tier_name} web tier to the box label '#{box_label}'" do
        tier = DynoTier.find_by(name: tier_name) || create(:dyno_tier, name: tier_name)
        create(:dyno_allocation, app_record: app, dyno_tier: tier, process_type: "web")
        component = described_class.new(apps: [ app ])
        expect(component.box_label(app.reload)).to eq(box_label)
      end
    end

    it "returns an em dash when there is no web allocation" do
      expect(described_class.new(apps: [ app ]).box_label(app)).to eq("—")
    end
  end
end
