# frozen_string_literal: true

require "openapi_helper"

# storage and buildpacks are retired: the routes stay mounted and answer 410
# with a typed error so old clients get a clear message, not a 404.
RSpec.describe "API v1 retired endpoints", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_id) { app_records(:one).id }
  error = { "$ref" => "#/components/schemas/Error" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name (not looked up; the endpoint is retired)" }

  {
    "storage" => [ [ :get, "show" ], [ :post, "create" ], [ :delete, "destroy" ] ],
    "buildpacks" => [ [ :get, "show" ], [ :post, "create" ], [ :patch, "update" ], [ :put, "replace" ], [ :delete, "destroy" ] ]
  }.each do |resource, ops|
    path "/api/v1/apps/{app_id}/#{resource}" do
      parameter app_param

      ops.each do |verb, action|
        send(verb, "#{action.capitalize} #{resource} (retired)") do
          operationId "#{resource}.#{action}"
          tags resource
          deprecated true
          security [ { bearer: [] } ]
          produces "application/json"

          response "410", "retired (#{resource == 'storage' ? 'storage_retired' : 'buildpacks_retired'})" do
            schema error
            run_test!
          end

          response "401", "missing or invalid token" do
            let(:Authorization) { nil }
            schema error
            run_test!
          end
        end
      end
    end
  end
end
