# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 ssh keys", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  key_schema = {
    type: :object,
    required: %w[id name fingerprint],
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string },
      fingerprint: { type: :string, nullable: true },
      created_at: { type: :string, format: "date-time" }
    }
  }

  path "/api/v1/ssh_keys" do
    get "List SSH public keys" do
      operationId "ssh_keys.list"
      tags "ssh_keys"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "keys" do
        schema type: :array, items: key_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Add an SSH public key" do
      operationId "ssh_keys.create"
      tags "ssh_keys"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[name public_key],
        properties: { name: { type: :string }, public_key: { type: :string } }
      }

      response "201", "key added" do
        let(:payload) do
          { name: "laptop", public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test@example" }
        end
        schema key_schema
        run_test!
      end

      response "422", "invalid key" do
        let(:payload) { { name: "bad", public_key: "not-a-key" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/ssh_keys/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Remove an SSH public key" do
      operationId "ssh_keys.delete"
      tags "ssh_keys"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "removed" do
        let(:id) do
          user.ssh_public_keys.create!(name: "tmp",
            public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test@example").id
        end
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "404", "key belongs to another user" do
        let(:id) do
          users(:admin).ssh_public_keys.create!(name: "theirs",
            public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl admin@example").id
        end
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
