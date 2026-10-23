# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiDebugger do
  let(:app) { app_records(:one) }
  let(:deploy) do
    app.deploys.create!(
      status: "failed",
      log: "bundle install failed\nmissing gem sqlite3",
      commit_sha: "abc1234"
    )
  end

  around do |example|
    original = ENV["ANTHROPIC_API_KEY"]
    example.run
  ensure
    ENV["ANTHROPIC_API_KEY"] = original
  end

  it "returns error when API key is missing" do
    ENV["ANTHROPIC_API_KEY"] = nil
    result = described_class.new(deploy).diagnose
    expect(result[:error]).to match(/No API key/)
  end

  it "returns error when deploy log is empty" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    deploy.update!(log: nil)
    result = described_class.new(deploy).diagnose
    expect(result[:error]).to match(/No deploy log/)
  end

  it "calls Anthropic API and returns diagnosis text on success" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    api_resp = OpenStruct.new(body: {
      content: [ { "text" => "Looks like a missing gem. Run bundle install." } ]
    }.to_json)

    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(api_resp)
    allow(Net::HTTP).to receive(:new).and_return(http)

    result = described_class.new(deploy).diagnose
    expect(result[:diagnosis]).to match(/missing gem/)
  end

  it "returns fallback message when API returns error payload" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    api_resp = OpenStruct.new(body: { error: { message: "rate limited" } }.to_json)

    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(api_resp)
    allow(Net::HTTP).to receive(:new).and_return(http)

    result = described_class.new(deploy).diagnose
    expect(result[:diagnosis]).to match(/rate limited/)
  end

  it "wraps network errors as AI diagnosis failures" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-fake"
    allow(Net::HTTP).to receive(:new).and_raise(SocketError.new("no dns"))
    result = described_class.new(deploy).diagnose
    expect(result).to eq(error: "AI diagnosis failed", error_code: :ai_provider_failed)
  end
end
