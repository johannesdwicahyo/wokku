# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 auth tokens", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/auth/tokens" do
    get "List active API tokens" do
      operationId "auth_tokens.list"
      tags "auth_tokens"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "tokens" do
        schema type: :array,
               items: {
                 type: :object,
                 required: %w[id name],
                 properties: {
                   id: { type: :string, format: :uuid },
                   name: { type: :string },
                   last_used_at: { type: :string, format: "date-time", nullable: true },
                   expires_at: { type: :string, format: "date-time", nullable: true },
                   created_at: { type: :string, format: "date-time" }
                 }
               }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Create an API token (plaintext returned once)" do
      operationId "auth_tokens.create"
      tags "auth_tokens"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string }, expires_at: { type: :string, format: "date-time" } }
      }

      response "201", "token created" do
        let(:payload) { { name: "ci" } }
        schema type: :object,
               required: %w[id token name],
               properties: { id: { type: :string, format: :uuid }, token: { type: :string }, name: { type: :string } }
        run_test!
      end
    end
  end

  path "/api/v1/auth/tokens/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Revoke an API token" do
      operationId "auth_tokens.delete"
      tags "auth_tokens"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "revoked" do
        let(:id) { ApiToken.create_with_token!(user: user, name: "victim")[0].id }
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "404", "token belongs to another user" do
        let(:id) { ApiToken.create_with_token!(user: users(:admin), name: "theirs")[0].id }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
