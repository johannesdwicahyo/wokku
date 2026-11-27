# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AddonsRackComponent, type: :component do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:app) { create(:app_record, team: team, server: server, name: "alpha") }
  let(:pg) { create(:database_service, server: server, name: "pg1", service_type: "postgres", status: :running) }
  let(:redis) { create(:database_service, server: server, name: "rd1", service_type: "redis", status: :error, last_error: "boom") }

  before { AppDatabase.create!(app_record: app, database_service: pg, alias_name: "DATABASE") }

  def render_rack(**opts)
    render_inline(described_class.new(databases: [ pg, redis ], group_by: "type", apps: [ app ], **opts))
  end

  it "renders rows for databases of different engines" do
    render_rack
    expect(page).to have_css("[data-rack-unit='pg1']", text: "alpha")
    expect(page).to have_css("[data-rack-unit='rd1']", text: "Redis")
    expect(page).to have_css("h2", text: "Postgres")
    expect(page).to have_css("h2", text: "Redis")
  end

  it "shows retry/destroy and the error for failed add-ons" do
    render_rack
    expect(page).to have_button("Retry")
    expect(page).to have_button("Destroy")
    expect(page).to have_text("boom")
  end

  it "groups by app" do
    render_inline(described_class.new(databases: [ pg, redis ], group_by: "app", apps: [ app ], orphans: [ redis ]))
    expect(page.all("h2").map(&:text)).to include("alpha")
    expect(page.all("h2").map(&:text)).not_to include("Unlinked")
    expect(page).to have_css("button[aria-pressed='true']", text: "By app")
  end

  it "renders orphans in their own section" do
    render_rack(orphans: [ redis ])
    expect(page).to have_css("#orphan_addons [data-rack-unit='rd1']")
  end

  it "warns on the bucket meter at 80% but not 79%" do
    hot = instance_double(ObjectStorageBucket, name: "wk-1", status: "active", used_gb: 80, quota_gb: 100, app_record: app)
    cool = instance_double(ObjectStorageBucket, name: "wk-2", status: "active", used_gb: 79, quota_gb: 100, app_record: app)
    render_rack(buckets: [ hot, cool ])
    expect(page).to have_css("[data-bucket='wk-1'] span.on.bg-warn")
    expect(page).to have_no_css("[data-bucket='wk-2'] span.bg-warn")
  end

  it "renders each db once by type, orphan included" do
    render_rack(orphans: [ redis ])
    expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(redis)}", count: 1)
  end

  it "gives repeats a scoped id when a db is linked to several apps" do
    app2 = create(:app_record, team: team, server: server, name: "bravo")
    AppDatabase.create!(app_record: app2, database_service: pg, alias_name: "DB2")
    render_inline(described_class.new(databases: [ pg ], group_by: "app", apps: [ app, app2 ]))
    expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(pg)}", count: 1)
    expect(page).to have_css("[data-rack-unit='pg1']", count: 2)
  end

  it "has no brutalist classes" do
    render_rack
    expect(page.native.to_html).not_to match(/shadow-brutal|border-1\.5/)
  end
end
