# frozen_string_literal: true

require "rails_helper"
require "yaml"

# Every public /api/v1 route must be in the contract.
RSpec.describe "OpenAPI completeness" do
  def internal
    %r{\A/api/v1/(agent/|logs/ingest|requests/ingest|openapi\.yaml)}
  end

  def routes
    Rails.application.routes.routes.filter_map do |r|
      path = r.path.spec.to_s.sub("(.:format)", "")
      next unless path.start_with?("/api/v1/") || path == "/api/v1"
      next if path.match?(internal)
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

  it "documents every public route" do
    expect(routes - documented).to eq([])
  end
end
