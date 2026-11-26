# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::NewAppAddonsComponent, type: :component do
  let(:user) { create(:user) }
  let(:team) { create(:team, owner: user) }
  let(:server) { create(:server) }
  let(:units) { { "cpu" => 24_000, "memory_gb" => 36_000, "disk_gb" => 1_000 } }

  before do
    create(:team_membership, team: team, user: user) unless team.team_memberships.exists?(user: user)
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
  end

  def render_it(**kw) = render_inline(described_class.new(user: user, server: server, team: team, **kw))

  it "renders the postgres catalog with shared and dedicated, env var, and exact shortcut shapes" do
    render_it
    group = page.find("[data-engine-group=postgres]", visible: :all)
    expect(group).to have_css("input[value=shared]", visible: :all)
    expect(group).to have_css("input[value=dedicated]", visible: :all)
    expect(group.find("input[value=shared]", visible: :all)["data-env"]).to eq("DATABASE_URL")
    { "small" => [ "0.25", "256", "1" ], "standard" => [ "0.5", "512", "5" ], "large" => [ "1.0", "1024", "10" ] }.each do |key, (c, m, d)|
      r = group.find("input[name=addon_size_postgres][value=#{key}]", visible: :all)
      expect([ r["data-cpu"], r["data-memory-mb"], r["data-disk-gb"] ]).to eq([ c, m, d ])
    end
    expect(group).to have_css("input[data-custom]", visible: :all)
    expect(page.find("[data-engine-group=mariadb] input[value=shared]", visible: :all)["data-env"]).to eq("MARIADB_URL, DATABASE_URL")
    expect(page.find("[data-engine-group=redis] input[value=shared]", visible: :all)["data-env"]).to eq("REDIS_URL")
  end

  it "shows Free for shared and prices dedicated shortcuts only with pricing" do
    render_it
    expect(page).to have_no_text("Rp")
    allow(Wokku.config).to receive(:pricing).and_return(double(unit_prices: units, monthly_idr: 12_000))
    render_it
    expect(page.find("[data-engine-group=postgres]", visible: :all).text(:all)).to include("Rp12,000")
    expect(page.find("[data-new-app-target=addons]")["data-free"]).to eq("Free")
  end

  it "keeps the draft sliders out of the posted names (builder draft, disk included)" do
    render_it
    expect(page).to have_css("[data-new-app-target=draftBuilder] input[name='addon_draft[disk_gb]']", visible: :all)
  end

  it "lists only the existing databases the attach service would accept" do
    ok = create(:database_service, server: server, creator: user, status: :running, name: "team-pg")
    create(:database_service, server: create(:server), creator: user, status: :running, name: "other-server")
    create(:database_service, server: server, creator: create(:user), status: :running, name: "strangers")
    create(:database_service, server: server, creator: user, status: :stopped, name: "stopped")
    foreign = create(:database_service, server: server, creator: user, status: :running, name: "foreign-linked")
    create(:app_record, server: server).app_databases.create!(database_service: foreign, alias_name: "POSTGRES")
    render_it
    expect(page).to have_css("[data-existing]", count: 1, visible: :all)
    expect(page).to have_css("[data-existing='#{ok.id}']", text: "team-pg", visible: :all)
    expect(page.find("[data-existing]", visible: :all).text(:all)).to include("postgres · running")
  end

  it "renders submitted items as rows with exactly the six hidden inputs, in order" do
    render_it(items: [ { "kind" => "shared", "engine" => "postgres" },
                       { "kind" => "dedicated", "engine" => "redis", "cpu" => "0.25", "memory_mb" => "256", "disk_gb" => "1" } ])
    rows = page.all("ul [data-new-app-row]")
    expect(rows.size).to eq(2)
    names = rows.first.all("input[type=hidden]", visible: :all).map { |i| i[:name] }
    expect(names).to eq(%w[kind engine cpu memory_mb disk_gb database_service_id].map { |f| "addons[][#{f}]" })
    expect(rows.first).to have_text("PostgreSQL · Shared")
    expect(rows.first).to have_text("Free")
    expect(rows.last).to have_text("Redis · Dedicated · 0.25 vCPU · 256 MB · 1 GB")
    expect(rows.last.find("input[data-field=cpu]", visible: :all).value).to eq("0.25")
  end

  it "disables Add at five with a note" do
    render_it(items: Array.new(5) { { "kind" => "shared", "engine" => "redis" } })
    expect(page).to have_css("button[disabled]", text: "Add an add-on")
    expect(page).to have_css("[data-new-app-target=limit]:not(.hidden)", text: "up to 5")
  end

  it "ships a blank row template with the same inputs" do
    render_it
    html = rendered_content
    tpl = html[/<template data-new-app-target="rowTemplate">.*?<\/template>/m]
    expect(tpl.scan("addons[][").size).to eq(6)
  end

  it "speaks Indonesian" do
    I18n.with_locale(:id) { render_it }
    expect(page).to have_text("Tambah add-on")
    expect(page).to have_text("Pakai yang sudah ada")
  end
end
