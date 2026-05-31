# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Acl do
  let(:fake_client_class) do
    Class.new do
      attr_reader :calls

      def initialize(responses = {})
        @responses = responses
        @calls = []
      end

      def run(cmd)
        @calls << cmd
        raise Dokku::Client::CommandError.new("boom") if @responses[:raise_on] && cmd.start_with?(@responses[:raise_on])
        @responses[:output] || ""
      end
    end
  end

  it "add runs acl:add with escaped args" do
    client = fake_client_class.new
    described_class.new(client).add("my-app", "user-42")
    expect(client.calls.first).to eq("acl:add my-app user-42")
  end

  it "add escapes shell-unsafe names" do
    client = fake_client_class.new
    described_class.new(client).add("app $(rm)", "user;rm")
    expect(client.calls.first).to match(/acl:add /)
    expect(client.calls.first).not_to match(/\$\(rm\)/)
  end

  it "remove runs acl:remove" do
    client = fake_client_class.new
    described_class.new(client).remove("app", "user-1")
    expect(client.calls.first).to eq("acl:remove app user-1")
  end

  it "list returns non-empty lines" do
    client = fake_client_class.new(output: "alice\n\nbob\n")
    expect(described_class.new(client).list("app")).to eq(%w[alice bob])
  end

  it "grant_team_apps continues after per-app CommandError" do
    client = fake_client_class.new(raise_on: "acl:add bad-app")
    acl = described_class.new(client)
    apps = [ OpenStruct.new(name: "good-app"), OpenStruct.new(name: "bad-app"), OpenStruct.new(name: "another") ]
    expect { acl.grant_team_apps("user-1", apps) }.not_to raise_error
    expect(client.calls.length).to eq(3)
  end

  it "revoke_all continues after CommandError" do
    client = fake_client_class.new(raise_on: "acl:remove bad")
    acl = described_class.new(client)
    apps = [ OpenStruct.new(name: "good"), OpenStruct.new(name: "bad"), OpenStruct.new(name: "other") ]
    expect { acl.revoke_all("user-1", apps) }.not_to raise_error
    expect(client.calls.length).to eq(3)
  end
end
