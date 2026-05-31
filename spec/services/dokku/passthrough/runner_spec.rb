# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Passthrough::Runner do
  let(:user) { users(:admin) }
  let(:server) { servers(:one) }
  let(:team) { teams(:one) }

  before do
    TeamMembership.create!(user: user, team: team, role: :admin) unless user.teams.any?
  end

  it "rejects empty args" do
    result = described_class.call(args: [], target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
    expect(result.error).to match(/Missing dokku command/i)
  end

  it "rejects non-array args" do
    result = described_class.call(args: "ps:list", target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
  end

  it "rejects more than 32 args" do
    result = described_class.call(args: Array.new(33, "x"), target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
    expect(result.error).to match(/too many/i)
  end

  it "rejects single arg longer than 256 chars" do
    result = described_class.call(args: [ "x" * 257 ], target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
    expect(result.error).to match(/too long/i)
  end

  it "rejects shell metacharacters" do
    %w[; && | ` $( > <].each do |meta|
      result = described_class.call(args: [ "ps:list#{meta}rm -rf" ], target: server, user: user, team: team)
      expect(result.ok?).to be_falsey, "expected '#{meta}' to be rejected"
      expect(result.error).to match(/metacharacter/i)
    end
  end

  it "rejects control characters and backslash" do
    [ "ps:list\nrm -rf", "ps:list\trm", "ps:list\x00rm", "ps:list\\rm" ].each do |arg|
      result = described_class.call(args: [ arg ], target: server, user: user, team: team)
      expect(result.ok?).to be_falsey, "expected #{arg.inspect} to be rejected"
      expect(result.error).to match(/metacharacter/i)
    end
  end

  it "rejects denied verb for non-admin" do
    result = described_class.call(args: [ "plugin:install", "foo" ], target: server, user: users(:one), team: team)
    expect(result.ok?).to be_falsey
    expect(result.error).to match(/blocked/i)
  end

  it "admin with force bypasses denylist" do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_return("ok")
    result = described_class.call(args: [ "plugin:install", "foo" ], target: server, user: user, team: team, force: true)
    expect(result.ok?).to be_truthy, result.error
  end

  it "happy path: invokes Dokku::Client and writes activity" do
    allow_any_instance_of(Dokku::Client).to receive(:run).with("ps:list myapp", timeout: 180).and_return("web.1: running")
    expect {
      result = described_class.call(args: [ "ps:list", "myapp" ], target: server, user: user, team: team)
      expect(result.ok?).to be_truthy, result.error
      expect(result.stdout).to eq("web.1: running")
      expect(result.exit_code).to eq(0)
    }.to change { Activity.count }.by(1)
    a = Activity.last
    expect(a.action).to eq("dokku_passthrough")
    expect(a.metadata["args"]).to eq([ "ps:list", "myapp" ])
  end

  it "non-zero exit propagates" do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(
      Dokku::Client::CommandError.new("boom", exit_code: 7, stderr: "nope")
    )
    result = described_class.call(args: [ "ps:list", "missing" ], target: server, user: user, team: team)
    expect(result.ok?).to be_truthy
    expect(result.exit_code).to eq(7)
    expect(result.stderr).to eq("nope")
  end

  it "timeout returns 504" do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(
      Dokku::Client::TimeoutError.new("Dokku command timed out after 180s: ps:list")
    )
    result = described_class.call(args: [ "ps:list" ], target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
    expect(result.status).to eq(:gateway_timeout)
    expect(result.error).to match(/timed out after 180s/)
  end

  it "connection failure returns 503" do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(
      Dokku::Client::ConnectionError.new("SSH authentication failed: bad key")
    )
    result = described_class.call(args: [ "ps:list" ], target: server, user: user, team: team)
    expect(result.ok?).to be_falsey
    expect(result.status).to eq(:service_unavailable)
  end
end
