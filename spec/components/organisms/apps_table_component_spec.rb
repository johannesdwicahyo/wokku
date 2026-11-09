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

  it "uses the latest succeeded deploy as last deploy" do
    create(:deploy, app_record: app, status: :succeeded, finished_at: 2.hours.ago)
    create(:deploy, app_record: app, status: :failed, finished_at: 1.minute.ago)
    component = described_class.new(apps: [ app ])
    expect(component.last_deployed_at(app)).to be_within(1.second).of(2.hours.ago)
  end

  it "renders the stats line under the name when stats are known" do
    app.update_columns(live_cpu_pct: 18.4, live_mem_used_mb: 410, live_metrics_at: 1.minute.ago)
    RequestAggregate.create!(app_record: app, bucket_start: 1.hour.ago, req_count: 4210)
    render_inline(described_class.new(apps: [ app ]))
    expect(page).to have_css("td div", text: "18% · 410 MB · 4.2k req/24h")
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
    # Tier vocabulary is the plan-billed path; per-resource shows the shape.
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

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
