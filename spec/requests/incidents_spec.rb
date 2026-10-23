# frozen_string_literal: true

require "rails_helper"

# Incidents are visible through the apps the caller can see; host (server)
# incidents only to the system admin. Bad query values are 422, not defaults.
RSpec.describe "API incidents", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:headers) { api_v1_headers(user) }

  it "lists open incidents of visible apps, newest first" do
    old = create(:incident, app_record: app_record, started_at: 2.hours.ago)
    resolved = create(:incident, app_record: app_record, started_at: 3.hours.ago, resolved_at: 150.minutes.ago)
    get "/api/v1/incidents", headers: headers
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.map { |i| i["id"] }
    expect(ids).to include(old.id)
    expect(ids).not_to include(resolved.id)
  end

  it "returns resolved ones with state=all, with duration" do
    resolved = create(:incident, app_record: app_record, started_at: 3.hours.ago, resolved_at: 150.minutes.ago)
    get "/api/v1/incidents", params: { state: "all" }, headers: headers
    row = response.parsed_body.find { |i| i["id"] == resolved.id }
    expect(row).to include("open" => false, "duration_seconds" => 1800, "subject_type" => "app", "app_name" => app_record.name)
  end

  it "hides other teams' app incidents and server incidents from non-admins" do
    foreign = create(:incident, app_record: create(:app_record))
    host = create(:incident, :for_server)
    get "/api/v1/incidents", headers: headers
    ids = response.parsed_body.map { |i| i["id"] }
    expect(ids).not_to include(foreign.id, host.id)
    get "/api/v1/incidents/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "shows server incidents to the system admin" do
    host = create(:incident, :for_server)
    get "/api/v1/incidents", headers: api_v1_headers(users(:admin))
    expect(response.parsed_body.map { |i| i["id"] }).to include(host.id)
  end

  it "filters by app name and pages with before + limit" do
    newer = create(:incident, app_record: app_record, started_at: 1.hour.ago, resolved_at: 50.minutes.ago)
    older = create(:incident, app_record: app_record, started_at: 5.hours.ago, resolved_at: 4.hours.ago)
    get "/api/v1/incidents", params: { state: "all", app_id: app_record.name, before: 2.hours.ago.iso8601, limit: 1 }, headers: headers
    expect(response.parsed_body.map { |i| i["id"] }).to eq([ older.id ])
    expect(newer).to be_persisted
  end

  [ { limit: "0" }, { limit: "abc" }, { limit: "500" }, { state: "closed" }, { before: "yesterday" } ].each do |bad|
    it "rejects #{bad.inspect} with 422 naming the field" do
      get "/api/v1/incidents", params: bad, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include(bad.keys.first.to_s)
    end
  end
end
