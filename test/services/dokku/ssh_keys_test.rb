require "test_helper"

class Dokku::SshKeysTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(output = "")
      @output = output
      @calls = []
    end
    def run(cmd)
      @calls << cmd
      @output
    end
  end

  test "add pipes the key through ssh-keys:add with escaped args" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).add("user-42", "ssh-ed25519 AAAA foo@bar")
    assert_match(/dokku ssh-keys:add user-42/, client.calls.first)
    assert_match(/ssh-ed25519/, client.calls.first)
  end

  test "add strips surrounding whitespace from the key" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).add("user-42", "  ssh-ed25519 AAAA foo  \n")
    refute_match(/\\n/, client.calls.first)
  end

  test "remove runs ssh-keys:remove" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).remove("user-42")
    assert_equal "ssh-keys:remove user-42", client.calls.first
  end

  test "list returns non-empty lines" do
    client = FakeClient.new("alice\nbob\n\n")
    assert_equal %w[alice bob], Dokku::SshKeys.new(client).list
  end
end
