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
              kind: { type: :string, enum: %w[personal org], nullable: true },
              slug: { type: :string, nullable: true },
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
          Deploy: {
            type: :object,
            required: %w[id status created_at],
            properties: {
              id: { type: :string, format: :uuid },
              status: { type: :string, enum: %w[pending building succeeded failed timed_out] },
              commit_sha: { type: :string, nullable: true },
              log: { type: :string, nullable: true, description: "Only on deploys.show" },
              started_at: { type: :string, format: "date-time", nullable: true },
              finished_at: { type: :string, format: "date-time", nullable: true },
              created_at: { type: :string, format: "date-time" }
            }
          },
          Release: {
            type: :object,
            required: %w[id version app_record_id created_at],
            properties: {
              id: { type: :string, format: :uuid },
              version: { type: :integer },
              description: { type: :string, nullable: true },
              app_record_id: { type: :string, format: :uuid },
              deploy_id: { type: :string, format: :uuid, nullable: true },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" }
            }
          },
          # Process report for ps.show: one entry per running task, keyed
          # status_<process>_<n> (e.g. status_web_1), value = task state.
          Process: {
            type: :object,
            required: %w[processes formation],
            properties: {
              processes: { type: :object, additionalProperties: { type: :string } },
              formation: { type: :object, additionalProperties: { type: :integer }, description: "desired process type => count" }
            }
          },
          # Raw DatabaseService JSON. `dsn` (credentials) only on databases.show
          # for member+; never on list/create or to viewers.
          Database: {
            type: :object,
            required: %w[id name service_type status server_id shared created_at updated_at],
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              service_type: { type: :string, description: "postgres, mariadb, mongodb, redis, memcached, ..." },
              status: { type: :string, enum: %w[running stopped creating error upgrading_provisioning upgrading_migrating upgrading_cutover upgrading_failed pending_destroy] },
              server_id: { type: :string, format: :uuid },
              tier_name: { type: :string, nullable: true },
              shared: { type: :boolean, description: "true = per-tenant database on a shared engine" },
              wokkud_managed: { type: :boolean },
              dsn: { type: :string, nullable: true, description: "Connection URL including credentials (e.g. postgres://user:pass@host:5432/db). Only on show, and only for team members/admins." },
              parent_service_id: { type: :string, format: :uuid, nullable: true },
              upgrade_source_id: { type: :string, format: :uuid, nullable: true },
              creator_id: { type: :string, format: :uuid, nullable: true },
              over_quota_at: { type: :string, format: "date-time", nullable: true },
              pending_destroy_at: { type: :string, format: "date-time", nullable: true },
              connection_limit: { type: :integer, nullable: true },
              storage_mb_quota: { type: :integer, nullable: true },
              shared_role_name: { type: :string, nullable: true },
              shared_db_name: { type: :string, nullable: true },
              live_db_bytes: { type: :integer, nullable: true },
              live_mem_used_mb: { type: :integer, nullable: true },
              live_metrics_at: { type: :string, format: "date-time", nullable: true },
              last_error: { type: :string, nullable: true },
              cpu: { type: :number, nullable: true },
              memory_mb: { type: :integer, nullable: true },
              disk_gb: { type: :integer, nullable: true },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" }
            }
          },
          Domain: {
            type: :object,
            required: %w[id hostname app_record_id ssl_enabled dns_verified created_at],
            properties: {
              id: { type: :string, format: :uuid },
              hostname: { type: :string },
              app_record_id: { type: :string, format: :uuid },
              ssl_enabled: { type: :boolean },
              dns_verified: { type: :boolean },
              pending_action: { type: :string, nullable: true, description: "e.g. ssl_enable while certificate issuance is queued" },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" }
            }
          },
          # Fields every signed-in user may see (servers.list, and servers.show
          # for non-admins). Platform-shared: ServerPolicy::Scope = all.
          ServerSummary: {
            type: :object,
            required: %w[id name host port status created_at heartbeat_status],
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              host: { type: :string },
              port: { type: :integer },
              status: { type: :string, enum: %w[connected unreachable auth_failed syncing] },
              heartbeat_status: { type: :string, enum: %w[unknown ok degraded down] },
              heartbeat_at: { type: :string, format: "date-time", nullable: true },
              created_at: { type: :string, format: "date-time" }
            }
          },
          # Full operator view, returned by servers.show/create to system admins
          # only (as_json minus ssh_private_key and ingest_token). Superset of
          # ServerSummary.
          Server: {
            type: :object,
            required: %w[id name host port status created_at heartbeat_status],
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              host: { type: :string },
              port: { type: :integer },
              status: { type: :string, enum: %w[connected unreachable auth_failed syncing] },
              heartbeat_status: { type: :string, enum: %w[unknown ok degraded down] },
              heartbeat_at: { type: :string, format: "date-time", nullable: true },
              created_at: { type: :string, format: "date-time" },
              updated_at: { type: :string, format: "date-time" },
              ssh_user: { type: :string, nullable: true },
              team_id: { type: :string, format: :uuid, nullable: true },
              region: { type: :string, nullable: true },
              cloud_provider: { type: :string, nullable: true },
              cloud_server_id: { type: :string, nullable: true },
              monthly_cost_cents: { type: :integer, nullable: true },
              capacity_total_mb: { type: :integer, nullable: true },
              live_cpu_pct: { type: :string, nullable: true, description: "Decimal serialized as a string" },
              live_mem_used_mb: { type: :integer, nullable: true },
              live_mem_total_mb: { type: :integer, nullable: true },
              live_container_count: { type: :integer, nullable: true },
              live_metrics_at: { type: :string, format: "date-time", nullable: true },
              docker_status: { type: :string, nullable: true },
              docker_status_checked_at: { type: :string, format: "date-time", nullable: true },
              vitals: { type: :object },
              agent_version: { type: :string, nullable: true },
              wokkud_builds_enabled: { type: :boolean },
              wokkud_router_enabled: { type: :boolean },
              wokkud_services_enabled: { type: :boolean },
              wokkud_cron_enabled: { type: :boolean }
            }
          },
          # Template from the bundled gallery (TemplateRegistry), rendered as-is.
          Template: {
            type: :object,
            required: %w[name slug description category tags deploy_method],
            properties: {
              name: { type: :string },
              slug: { type: :string },
              description: { type: :string, nullable: true },
              category: { type: :string },
              icon: { type: :string, nullable: true },
              icon_slug: { type: :string, nullable: true },
              icon_color: { type: :string, nullable: true },
              version: { type: :string, nullable: true },
              repo: { type: :string, nullable: true },
              branch: { type: :string, nullable: true },
              tags: { type: :array, items: { type: :string } },
              deploy_method: { type: :string, description: "e.g. docker_image, git" },
              docker_image: { type: :string, nullable: true },
              container_port: { type: :integer, nullable: true },
              addons: { type: :array, items: { type: :object } },
              env: { type: :object, additionalProperties: { type: :string } },
              post_deploy: { type: :string, nullable: true },
              healthcheck: { nullable: true },
              command: { type: :string, nullable: true },
              min_tier: { type: :string, nullable: true },
              set_url: { type: :array, items: { type: :string } },
              generate_secrets: { type: :array, items: { type: :string } },
              alias_env: { type: :object },
              storage_mounts: { type: :array, items: {} },
              shared_engines: { type: :array, items: { type: :string } },
              dedicated_db_engine: { type: :string, nullable: true },
              builder: { nullable: true },
              services: { type: :object }
            }
          },
          Device: {
            type: :object,
            required: %w[token platform],
            properties: {
              token: { type: :string },
              platform: { type: :string, enum: %w[ios android macos] },
              provider: { type: :string, enum: %w[expo apns], default: "expo" }
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
