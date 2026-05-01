require "shellwords"

module Dokku
  class SshKeys
    def initialize(client)
      @client = client
    end

    # Add a user's SSH public key to the Dokku server
    # name: unique identifier (e.g., "user-42" or "user-42-key-1")
    # public_key: the SSH public key string (e.g., "ssh-ed25519 AAAA... user@host")
    def add(name, public_key)
      # When we SSH in as the `dokku` user, Dokku's own restricted shell
      # treats the command string as a single subcommand — `echo key | ...`
      # never works because `echo` isn't a Dokku subcommand. Instead,
      # invoke `ssh-keys:add <name>` directly and stream the pubkey on
      # stdin. Dokku reads stdin when no file path is given.
      escaped_name = Shellwords.escape(name)
      @client.run("ssh-keys:add #{escaped_name}", stdin: public_key.strip + "\n")
    end

    # Remove a user's SSH key from the Dokku server
    def remove(name)
      escaped_name = Shellwords.escape(name)
      @client.run("ssh-keys:remove #{escaped_name}")
    end

    # List all SSH keys on the server
    def list
      output = @client.run("ssh-keys:list")
      output.lines.map(&:strip).reject(&:empty?)
    end
  end
end
