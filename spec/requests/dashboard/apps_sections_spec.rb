# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps deferred sections", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when unauthenticated" do
    get sections_dashboard_apps_path(section: :list)
    expect(response).to have_http_status(:redirect)
  end

  context "when signed in" do
    before { sign_in user }

    after { Wokku.config.apps_index_side_sections = nil }

    it "renders the list section as a turbo-frame with overview and rack" do
      create(:app_record, team: user.teams.first, server: create(:server, team: user.teams.first))
      get sections_dashboard_apps_path(section: :list)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="apps_list"')
      expect(response.body).to include("Overview").and match(/Apps · \d+/)
      expect(response.body).not_to include("Rp")
    end

    it "renders the in-progress deploy track inside the list frame" do
      team = user.teams.first
      app = create(:app_record, team: team, server: create(:server, team: team))
      create(:deploy, app_record: app, status: :building)
      get sections_dashboard_apps_path(section: :list)
      expect(response.body).to include("Deploy in progress")
      expect(response.body).to include('data-deploy-reload-frame-value="apps_list"')
    end

    it "renders id labels under ?locale=id" do
      create(:app_record, team: user.teams.first, server: create(:server, team: user.teams.first))
      get sections_dashboard_apps_path(section: :list, locale: "id")
      expect(response.body).to include("Armada · per proses")
    end

    it "keeps the list query count flat as apps grow" do
      team = user.teams.first
      server = create(:server, team: team)
      counter = lambda do
        n = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless %w[SCHEMA TRANSACTION].include?(p[:name]) || p[:cached] }
        get sections_dashboard_apps_path(section: :list)
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end
      populate = lambda do |count|
        count.times do
          app = create(:app_record, team: team, server: server, status: :running, live_metrics_at: Time.current)
          create(:domain, app_record: app)
          create(:dyno_allocation, app_record: app, process_type: "web", count: 2)
          create(:deploy, :succeeded, app_record: app, finished_at: 1.hour.ago)
        end
      end
      populate.call(2)
      counter.call # warm caches
      small = counter.call
      populate.call(10)
      expect(counter.call).to eq(small)
    end

    it "renders the side section with Databases and seam partials" do
      Wokku.config.apps_index_side_sections = ->(_v, _t) { [ { partial: "dashboard/object_storages/section", locals: { app: app_records(:one) } } ] }
      create(:database_service, name: "side-pg", server: create(:server, team: user.teams.first), creator: user)
      get sections_dashboard_apps_path(section: :side)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="apps_side"').and include("Databases")
      expect(response.body).to include("S3-compatible bucket for uploads and files")
    end

    it "still renders the side frame when the seam raises, with no Rp on self-host" do
      Wokku.config.apps_index_side_sections = ->(_v, _t) { raise "boom" }
      get sections_dashboard_apps_path(section: :side)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="apps_side"')
      expect(response.body).not_to include("Rp")
    end

    it "no longer serves the activity section" do
      get sections_dashboard_apps_path(section: :activity)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown section" do
      get sections_dashboard_apps_path(section: :bogus)
      expect(response).to have_http_status(:not_found)
    end
  end
end
