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
      # Write key to a temp file on the server and import it
      escaped_name = Shellwords.escape(name)
      escaped_key = Shellwords.escape(public_key.strip)
      @client.run("echo #{escaped_key} | dokku ssh-keys:add #{escaped_name}")
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
