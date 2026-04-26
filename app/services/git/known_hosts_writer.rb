require "fileutils"
require "open3"

module Git
  # Maintains /etc/wokku/known_hosts (inside the container, bind-mounted
  # from the host) with one verified host-key entry per Dokku server.
  #
  # The gateway uses this file with `StrictHostKeyChecking=yes` so a
  # man-in-the-middle between us and a Dokku host is refused instead of
  # silently accepted.
  #
  # Typical use:
  #
  #   Git::KnownHostsWriter.add(server)   # on Server#after_create_commit
  #   Git::KnownHostsWriter.remove(server)# on Server#after_destroy_commit
  #
  # Both operations are idempotent. A no-op if no path is configured
  # (dev/test), so callers don't need to branch.
  class KnownHostsWriter
    class Error < StandardError; end

    class << self
      # Fetch the server's host key via ssh-keyscan and upsert it into
      # the known_hosts file. Returns the line written, or nil if
      # skipped.
      def add(server, path: configured_path)
        return nil if path.blank?

        line = scan(server)
        FileUtils.mkdir_p(File.dirname(path))
        FileUtils.touch(path) unless File.exist?(path)
        File.chmod(0o644, path)

        rewrite_atomically(path) do |existing|
          keep = existing.reject { |l| matches_host?(l, host_id(server)) }
          keep << line
          keep
        end
        line
      end

      # Remove all entries for a server from the file. Idempotent.
      def remove(server, path: configured_path)
        return nil if path.blank?
        return nil unless File.exist?(path)

        rewrite_atomically(path) do |existing|
          existing.reject { |l| matches_host?(l, host_id(server)) }
        end
      end

      # Where to write. Blank in dev/test by default.
      def configured_path
        ENV["WOKKU_GATEWAY_KNOWN_HOSTS_PATH"].presence
      end

      # Run `ssh-keyscan` to fetch the server's host key. Returns a
      # known_hosts-format line.
      def scan(server)
        port = server.port.presence || 22
        cmd = [ "ssh-keyscan", "-T", "5", "-t", "ed25519,rsa", "-p", port.to_s, server.host ]
        out, err, status = Open3.capture3(*cmd)
        unless status.success? && out.strip.length > 0
          raise Error, "ssh-keyscan failed for #{server.host}:#{port} — #{err.strip}"
        end
        # ssh-keyscan may return multiple lines (one per key type); take
        # only ed25519 if present, else the first line.
        lines = out.strip.lines
        ed25519 = lines.find { |l| l.include?("ssh-ed25519") }
        (ed25519 || lines.first).strip
      end

      private

      def host_id(server)
        port = server.port.presence || 22
        port == 22 ? server.host : "[#{server.host}]:#{port}"
      end

      # A known_hosts line begins with one or more comma-separated hosts
      # before the key type. Match if `host_ident` appears in that list.
      def matches_host?(line, host_ident)
        return false if line.start_with?("#")
        first = line.split(/\s+/, 2).first.to_s
        first.split(",").include?(host_ident)
      end

      def rewrite_atomically(path)
        existing = File.readlines(path, chomp: true)
        new_lines = yield(existing)
        tmp = "#{path}.tmp.#{Process.pid}"
        File.open(tmp, "w", 0o644) do |f|
          f.write(new_lines.join("\n"))
          f.write("\n") unless new_lines.empty?
        end
        File.rename(tmp, path)
      end
    end
  end
end
