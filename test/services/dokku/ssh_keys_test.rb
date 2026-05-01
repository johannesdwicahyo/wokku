require "test_helper"

class Dokku::SshKeysTest < ActiveSupport::TestCase
  class FakeClient
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

  test "add invokes ssh-keys:add with the key streamed on stdin" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).add("user-42", "ssh-ed25519 AAAA foo@bar")
    call = client.calls.first
    # Command must NOT contain the pubkey — dokku's restricted shell
    # treats the command string as a single subcommand, so `echo ... |`
    # never worked (echo isn't a dokku subcommand).
    assert_equal "ssh-keys:add user-42", call[:cmd]
    assert_match(/ssh-ed25519 AAAA foo@bar/, call[:stdin])
  end

  test "add strips surrounding whitespace from the key" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).add("user-42", "  ssh-ed25519 AAAA foo  \n")
    # stdin should be the trimmed key plus a single trailing newline,
    # no embedded whitespace runs.
    assert_equal "ssh-ed25519 AAAA foo\n", client.calls.first[:stdin]
  end

  test "remove runs ssh-keys:remove" do
    client = FakeClient.new
    Dokku::SshKeys.new(client).remove("user-42")
    assert_equal "ssh-keys:remove user-42", client.calls.first[:cmd]
  end

  test "list returns non-empty lines" do
    client = FakeClient.new("alice\nbob\n\n")
    assert_equal %w[alice bob], Dokku::SshKeys.new(client).list
  end
end
