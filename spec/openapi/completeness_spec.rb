# frozen_string_literal: true

require "rails_helper"
require "yaml"

# Every public /api/v1 route must be in the contract. UNDOCUMENTED shrinks
# as batches land and must be empty at the end of sub-project 1.
RSpec.describe "OpenAPI completeness" do
  INTERNAL = %r{\A/api/v1/(agent/|logs/ingest|requests/ingest|openapi\.yaml)}
  UNDOCUMENTED = [
    "DELETE /api/v1/servers/{id}",
    "DELETE /api/v1/tunnels/{id}",
    "GET /api/v1/apps/{app_id}/dynos",
    "GET /api/v1/billing/current_plan",
    "GET /api/v1/billing/usage",
    "GET /api/v1/dyno_tiers",
    "GET /api/v1/servers",
    "GET /api/v1/servers/{id}",
    "GET /api/v1/servers/{id}/status",
    "GET /api/v1/templates",
    "GET /api/v1/templates/{id}",
    "PATCH /api/v1/apps/{app_id}/dynos/{id}",
    "POST /api/v1/billing/create_checkout",
    "POST /api/v1/billing/portal",
    "POST /api/v1/servers",
    "POST /api/v1/servers/{id}/dokku",
    "POST /api/v1/templates/deploy",
    "POST /api/v1/tunnels",
    "POST /api/v1/tunnels/authorize/{plugin_secret}",
    "PUT /api/v1/apps/{app_id}/dynos/{id}",
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
