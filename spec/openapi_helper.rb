# frozen_string_literal: true

require "rails_helper"

# OpenAPI contract (spec 2026-10-22-api-contract-parity-design). rswag specs
# under spec/openapi/ both test /api/v1 and generate openapi/v1.cloud.yaml;
# `rake openapi:engine` derives openapi/v1.yaml (operations not tagged
# "cloud"). Run bin/openapi-check after changing any API response.
RSpec.configure do |config|
  config.openapi_root = Rails.root.join("openapi").to_s
  config.openapi_format = :yaml
  config.openapi_specs = {
    "v1.cloud.yaml" => {
      openapi: "3.0.3",
      info: { title: "Wokku API", version: "v1" },
      servers: [ { url: "https://wokku.cloud" } ],
      components: {
        securitySchemes: { bearer: { type: :http, scheme: :bearer } },
        schemas: {
          Error: {
            type: :object,
            required: %w[code message],
            properties: {
              code: { type: :string },
              message: { type: :string },
              hint: { type: :string, nullable: true },
              details: { nullable: true }
            }
          }
        }
      },
      security: [ { bearer: [] } ],
      paths: {}
    }
  }
end
