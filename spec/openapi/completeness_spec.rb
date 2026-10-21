# frozen_string_literal: true

require "rails_helper"
require "yaml"

# Every public /api/v1 route must be in the contract. UNDOCUMENTED shrinks
# as batches land and must be empty at the end of sub-project 1.
RSpec.describe "OpenAPI completeness" do
  INTERNAL = %r{\A/api/v1/(agent/|logs/ingest|requests/ingest|openapi\.yaml)}
  UNDOCUMENTED = [
    "DELETE /api/v1/apps/{app_id}/addons/shared/{engine}",
    "DELETE /api/v1/apps/{app_id}/addons/{id}",
    "DELETE /api/v1/apps/{app_id}/buildpacks",
    "DELETE /api/v1/apps/{app_id}/config",
    "DELETE /api/v1/apps/{app_id}/dev_sessions/{id}",
    "DELETE /api/v1/apps/{app_id}/domains/{id}",
    "DELETE /api/v1/apps/{app_id}/previews/{pr_number}",
    "DELETE /api/v1/apps/{app_id}/scheduled_tasks/{id}",
    "DELETE /api/v1/apps/{app_id}/storage",
    "DELETE /api/v1/databases/{id}",
    "DELETE /api/v1/servers/{id}",
    "DELETE /api/v1/tunnels/{id}",
    "GET /api/v1/apps/{app_id}/addons",
    "GET /api/v1/apps/{app_id}/buildpacks",
    "GET /api/v1/apps/{app_id}/checks",
    "GET /api/v1/apps/{app_id}/config",
    "GET /api/v1/apps/{app_id}/deploys",
    "GET /api/v1/apps/{app_id}/deploys/{id}",
    "GET /api/v1/apps/{app_id}/domains",
    "GET /api/v1/apps/{app_id}/dynos",
    "GET /api/v1/apps/{app_id}/logs",
    "GET /api/v1/apps/{app_id}/previews",
    "GET /api/v1/apps/{app_id}/ps",
    "GET /api/v1/apps/{app_id}/releases",
    "GET /api/v1/apps/{app_id}/releases/{id}",
    "GET /api/v1/apps/{app_id}/runs/{id}",
    "GET /api/v1/apps/{app_id}/scheduled_tasks",
    "GET /api/v1/apps/{app_id}/storage",
    "GET /api/v1/billing/current_plan",
    "GET /api/v1/billing/usage",
    "GET /api/v1/databases",
    "GET /api/v1/databases/{database_id}/backups",
    "GET /api/v1/databases/{database_id}/backups/{id}/download",
    "GET /api/v1/databases/{id}",
    "GET /api/v1/databases/{id}/monitor",
    "GET /api/v1/doctor",
    "GET /api/v1/dyno_tiers",
    "GET /api/v1/servers",
    "GET /api/v1/servers/{id}",
    "GET /api/v1/servers/{id}/status",
    "GET /api/v1/templates",
    "GET /api/v1/templates/{id}",
    "PATCH /api/v1/apps/{app_id}/buildpacks",
    "PATCH /api/v1/apps/{app_id}/checks",
    "PATCH /api/v1/apps/{app_id}/config",
    "PATCH /api/v1/apps/{app_id}/dynos/{id}",
    "PATCH /api/v1/apps/{app_id}/ps",
    "POST /api/v1/apps/{app_id}/addons",
    "POST /api/v1/apps/{app_id}/addons/dedicated",
    "POST /api/v1/apps/{app_id}/addons/shared",
    "POST /api/v1/apps/{app_id}/buildpacks",
    "POST /api/v1/apps/{app_id}/deploys",
    "POST /api/v1/apps/{app_id}/deploys/uploads",
    "POST /api/v1/apps/{app_id}/dev_sessions",
    "POST /api/v1/apps/{app_id}/domains",
    "POST /api/v1/apps/{app_id}/domains/{id}/ssl",
    "POST /api/v1/apps/{app_id}/releases/{id}/rollback",
    "POST /api/v1/apps/{app_id}/scheduled_tasks",
    "POST /api/v1/apps/{app_id}/storage",
    "POST /api/v1/billing/create_checkout",
    "POST /api/v1/billing/portal",
    "POST /api/v1/databases",
    "POST /api/v1/databases/{database_id}/backups",
    "POST /api/v1/databases/{database_id}/backups/{id}/restore",
    "POST /api/v1/databases/{id}/import",
    "POST /api/v1/databases/{id}/link",
    "POST /api/v1/databases/{id}/unlink",
    "POST /api/v1/servers",
    "POST /api/v1/servers/{id}/dokku",
    "POST /api/v1/templates/deploy",
    "POST /api/v1/tunnels",
    "POST /api/v1/tunnels/authorize/{plugin_secret}",
    "PUT /api/v1/apps/{app_id}/buildpacks",
    "PUT /api/v1/apps/{app_id}/checks",
    "PUT /api/v1/apps/{app_id}/config",
    "PUT /api/v1/apps/{app_id}/dynos/{id}",
    "PUT /api/v1/apps/{app_id}/ps",
  ].freeze

  def routes
    Rails.application.routes.routes.filter_map do |r|
      path = r.path.spec.to_s.sub("(.:format)", "")
      next unless path.start_with?("/api/v1/") || path == "/api/v1"
      next if path.match?(INTERNAL)
      verb = r.verb.to_s
      next if verb.empty?
      verb.split("|").map { |v| "#{v} #{path.gsub(/:(\w+)/, '{\1}')}" }
    end.flatten.uniq.sort
  end

  def documented
    doc = YAML.safe_load_file(Wokku.config.openapi_path, aliases: true)
    doc.fetch("paths", {}).flat_map do |path, ops|
      ops.keys.reject { _1 == "parameters" }.map { |v| "#{v.upcase} #{path}" }
    end.sort
  end

  it "documents every public route (except the shrinking UNDOCUMENTED list)" do
    expect(routes - documented - UNDOCUMENTED).to eq([])
  end

  it "keeps UNDOCUMENTED honest (no entries that are now documented or gone)" do
    expect(UNDOCUMENTED - (routes - documented)).to eq([])
  end
end
