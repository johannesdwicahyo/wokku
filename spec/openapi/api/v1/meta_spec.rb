# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 meta", type: :request do
  path "/api/v1/meta" do
    get "Version and client-compatibility probe" do
      operationId "meta.show"
      tags "meta"
      security []
      produces "application/json"

      response "200", "versions" do
        schema type: :object,
               required: %w[api_version min_cli_version min_mcp_version server_time],
               properties: {
                 api_version: { type: :string, nullable: true },
                 min_cli_version: { type: :string },
                 min_mcp_version: { type: :string },
                 server_time: { type: :string, format: "date-time" },
                 client: { type: :object, nullable: true }
               }
        run_test!
      end
    end
  end
end
