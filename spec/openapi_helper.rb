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
          # Real shape of ApiErrors.payload (error_code/retryable), not the
          # earlier code/message sketch. `errors` is the legacy copy of details.
          Error: {
            type: :object,
            required: %w[error error_code retryable],
            properties: {
              error: { type: :string },
              error_code: { type: :string },
              hint: { type: :string, nullable: true },
              retryable: { type: :boolean },
              details: { nullable: true },
              errors: { nullable: true }
            }
          },
          Team: {
            type: :object,
            required: %w[id name owner_id],
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              owner_id: { type: :string, format: :uuid },
              plan_id: { type: :string, format: :uuid, nullable: true },
              kind: { type: :string, enum: %w[personal org], nullable: true },
              slug: { type: :string, nullable: true },
              trial_ends_at: { type: :string, format: "date-time", nullable: true },
              billing_anchor_date: { type: :string, format: :date, nullable: true },
              payment_method_type: { type: :string },
              billing_model: { type: :string },
              billing_credit_idr: { type: :integer },
              billing_switched_on: { type: :string, format: :date, nullable: true },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" }
            }
          },
          TeamMember: {
            type: :object,
            required: %w[id user_id email role],
            properties: {
              id: { type: :string, format: :uuid },
              user_id: { type: :string, format: :uuid },
              email: { type: :string },
              role: { type: :string, enum: %w[viewer member admin] }
            }
          },
          # Raw AppRecord JSON (webhook secrets are stripped). The list endpoint
          # returns only the first block of fields; show/create add git_remote etc.
          App: {
            type: :object,
            required: %w[id name server_id team_id status created_at],
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              server_id: { type: :string, format: :uuid },
              team_id: { type: :string, format: :uuid },
              status: { type: :string, enum: %w[running stopped crashed deploying sleeping created] },
              is_preview: { type: :boolean },
              pr_number: { type: :integer, nullable: true },
              parent_app_id: { type: :string, format: :uuid, nullable: true },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" },
              created_by_id: { type: :string, format: :uuid },
              deploy_branch: { type: :string, nullable: true },
              box_size: { type: :string, nullable: true },
              git_repository_url: { type: :string, nullable: true },
              github_repo_full_name: { type: :string, nullable: true },
              pending_action: { type: :string, nullable: true },
              container_port: { type: :integer },
              cloudflare_proxied: { type: :boolean },
              https_redirect: { type: :boolean },
              maintenance_mode: { type: :boolean },
              enabled_shared_engines: { type: :array, items: { type: :string } },
              uptime_status: { type: :string },
              deploy_locked_at: { type: :string, format: "date-time", nullable: true },
              last_commit_sha: { type: :string, nullable: true },
              git_remote: { type: :string },
              push_instructions: { type: :string },
              host_status: { type: :string, nullable: true },
              host_heartbeat_at: { type: :string, format: "date-time", nullable: true },
              warnings: { type: :array, items: { type: :string } }
            }
          },
          Device: {
            type: :object,
            required: %w[token platform],
            properties: {
              token: { type: :string },
              platform: { type: :string, enum: %w[ios android] }
            }
          },
          Activity: {
            type: :object,
            required: %w[id action description created_at],
            properties: {
              id: { type: :string, format: :uuid },
              action: { type: :string },
              description: { type: :string },
              target_name: { type: :string, nullable: true },
              target_type: { type: :string, nullable: true },
              created_at: { type: :string, format: "date-time" }
            }
          }
        }
      },
      security: [ { bearer: [] } ],
      paths: {}
    }
  }
end
