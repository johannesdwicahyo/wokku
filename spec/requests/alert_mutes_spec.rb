# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API alert mutes validation", type: :request do
  let(:headers) { api_v1_headers(users(:one)) }

  [
    [ { event: "app_created" }, "event" ],
    [ { event: "app_down", until: "soon" }, "until" ],
    [ { event: "app_down", until: 1.hour.ago.iso8601 }, "until" ]
  ].each do |payload, field|
    it "rejects #{payload.inspect} with 422 naming #{field}" do
      post "/api/v1/alert_mutes", params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include(field)
    end
  end

  it "survives a concurrent duplicate POST (RecordNotUnique) with one row" do
    user = users(:one)
    calls = 0
    allow_any_instance_of(AlertMute).to receive(:update!).and_wrap_original do |m, *args|
      calls += 1
      raise ActiveRecord::RecordNotUnique, "dup" if calls == 1

      m.call(*args)
    end
    post "/api/v1/alert_mutes", params: { event: "app_down" }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(user.alert_mutes.where(event: "app_down").count).to eq(1)
  end
end
