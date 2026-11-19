# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain, "wildcard hostnames" do
  let(:app_record) { app_records(:one) }

  def build(host) = app_record.domains.build(hostname: host)

  it "accepts a leading *. on a registrable domain or deeper" do
    expect(build("*.wicara.cloud")).to be_valid
    expect(build("*.tenants.example.co.id")).to be_valid
  end

  it "rejects malformed or overly broad wildcards" do
    [ "*.co.id", "*.com", "a.*.example.com", "*example.com", "**.example.com", "*.*.example.com", "*" ].each do |host|
      expect(build(host)).not_to be_valid, host
    end
  end

  it "rejects wildcards under the platform's own zones" do
    zone = Wokku.config.owned_domains.first
    expect(build("*.#{zone}")).not_to be_valid
  end

  it "knows its parent" do
    expect(build("*.wicara.cloud").wildcard_parent).to eq("wicara.cloud")
    expect(build("app.wicara.cloud").wildcard_parent).to be_nil
  end
end
