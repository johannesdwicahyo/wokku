# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::SshKeys do
  let(:fake_client_class) do
    Class.new do
      attr_reader :calls

      def initialize(output = "")
        @output = output
        @calls = []
      end

      def run(cmd, stdin: nil)
        @calls << { cmd: cmd, stdin: stdin }
        @output
      end
    end
  end

  it "add invokes ssh-keys:add with the key streamed on stdin" do
    client = fake_client_class.new
    described_class.new(client).add("user-42", "ssh-ed25519 AAAA foo@bar")
    call = client.calls.first
    expect(call[:cmd]).to eq("ssh-keys:add user-42")
    expect(call[:stdin]).to match(/ssh-ed25519 AAAA foo@bar/)
  end

  it "add strips surrounding whitespace from the key" do
    client = fake_client_class.new
    described_class.new(client).add("user-42", "  ssh-ed25519 AAAA foo  \n")
    expect(client.calls.first[:stdin]).to eq("ssh-ed25519 AAAA foo\n")
  end

  it "remove runs ssh-keys:remove" do
    client = fake_client_class.new
    described_class.new(client).remove("user-42")
    expect(client.calls.first[:cmd]).to eq("ssh-keys:remove user-42")
  end

  it "list returns non-empty lines" do
    client = fake_client_class.new("alice\nbob\n\n")
    expect(described_class.new(client).list).to eq(%w[alice bob])
  end
end
