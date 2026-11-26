# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps#show overview", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:team) { user.teams.first }
  let(:server) { create(:server, team: team) }
  let(:record) { create(:app_record, team: team, server: server, status: :running, name: "shop") }

  before { sign_in user }

  def add_release
    v = record.releases.maximum(:version).to_i + 1
    d = create(:deploy, :succeeded, app_record: record, image_ref: "127.0.0.1:5000/x/shop:#{v}", finished_at: 1.hour.ago)
    Release.create!(app_record: record, deploy: d, version: v)
  end

  def populate(releases:, domains:, databases:, processes:)
    releases.times { add_release }
    domains.times { |i| create(:domain, app_record: record, hostname: "d#{i}-#{SecureRandom.hex(3)}.example.com") }
    databases.times { |i| create(:app_database, app_record: record, database_service: create(:database_service, server: server, name: "pg#{i}-#{SecureRandom.hex(3)}"), alias_name: "DB#{i}") }
    types = %w[web worker clock].first(processes)
    types.each { |t| create(:dyno_allocation, app_record: record, process_type: t) unless record.dyno_allocations.exists?(process_type: t) }
  end

  it "renders for a member with controls" do
    populate(releases: 2, domains: 1, databases: 1, processes: 1)
    get "/dashboard/apps/#{record.id}"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("app_live_log")
    expect(response.body).to include("Roll back")
  end

  MUTATORS = "button:not([type=button]), input[type=submit], [data-turbo-method]"

  def mutators(html)
    page = Capybara.string(html)
    page.all("form").reject { |f| f[:action].to_s.include?("/dashboard/locale") }.flat_map { |f| f.all(MUTATORS).to_a } +
      page.all("[data-turbo-method]").to_a
  end

  it "shows a member Roll back, Restart and scaling controls but a viewer none" do
    populate(releases: 2, domains: 1, databases: 0, processes: 1)
    get "/dashboard/apps/#{record.id}"
    member_html = response.body
    expect(member_html).to include("Roll back").and include("Restart")
    expect(mutators(member_html)).not_to be_empty
    expect(Capybara.string(member_html)).to have_css("#app_tab_content form button, #app_tab_content form input[type=submit]")

    viewer = User.create!(email: "viewer-show@example.com", password: "password123456")
    TeamMembership.create!(user: viewer, team: team, role: :viewer)
    sign_in viewer
    get "/dashboard/apps/#{record.id}"
    expect(response).to have_http_status(:success)
    expect(mutators(response.body)).to be_empty
    expect(response.body).not_to include("Roll back")
  end

  describe "pricing seam" do
    after { Wokku.config.pricing = nil }

    def page_with_pricing(pricing)
      Wokku.config.pricing = pricing
      populate(releases: 2, domains: 1, databases: 1, processes: 2)
      get "/dashboard/apps/#{record.id}"
      Capybara.string(response.body)
    end

    it "shows no Rupiah on NullPricing" do
      page = page_with_pricing(Wokku::Providers::NullPricing.new)
      expect(page.find("#app_tab_content").text).not_to include("Rp")
      expect(page.text).not_to include("Rp")
    end

    it "shows Rupiah when pricing returns a number" do
      stub = Class.new(Wokku::Providers::NullPricing) { def monthly_idr(*, **) = 32_000 }.new
      expect(page_with_pricing(stub).find("#app_tab_content").text).to include("Rp")
    end
  end

  it "renders a brand-new app" do
    get "/dashboard/apps/#{record.id}"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("—").and include("No deploys yet")
  end

  it "does no SSH and keeps the query count flat as the app grows" do
    expect(Hosts::Ssh).not_to receive(:new)
    expect(Apps::LogReader).not_to receive(:recent)
    counter = lambda do
      n = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless %w[SCHEMA TRANSACTION].include?(p[:name]) || p[:cached] }
      get "/dashboard/apps/#{record.id}"
      ActiveSupport::Notifications.unsubscribe(sub)
      n
    end
    populate(releases: 2, domains: 1, databases: 1, processes: 1)
    counter.call # warm caches
    small = counter.call
    populate(releases: 12, domains: 5, databases: 4, processes: 3)
    expect(counter.call).to eq(small)
  end

  it "has no English panel labels under id" do
    populate(releases: 2, domains: 1, databases: 1, processes: 2)
    get "/dashboard/apps/#{record.id}?locale=id"
    text = Capybara.string(response.body).find("#app_tab_content").text
    ["Processes", "Live logs", "Deploys", "Connected", "Domains", "Resources", "Roll back", "Restart", "Pause", "Metrics", "No deploys yet"].each { |w| expect(text).not_to include(w) }
  end
end
