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
end
