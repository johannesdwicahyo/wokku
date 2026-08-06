require "shellwords"

module Apps
  module DevSession
    class AuthorizedKeysWriter
      PATH = "/etc/wokku/dev-session-authorized-keys".freeze
      FORCE_COMMAND = "/opt/wokku/bin/wokku-dev-shell".freeze

      def initialize(app)
        @app = app
      end

      def append(ssh_principal:, user_pubkey:, db_remote_host:, db_remote_port:)
        line = build_line(ssh_principal, user_pubkey, db_remote_host, db_remote_port)
        # sshd's StrictModes rejects AuthorizedKeysFile entries that aren't
        # root-owned when authenticating as a non-root user, so we keep the
        # file root:root and write through sudo. The NOPASSWD sudoers fragment
        # whitelists exactly `tee -a` against this path — see provision script.
        # Escape single quotes in the line for safe single-quoted shell interpolation.
        escaped = line.gsub("'", "'\\\\''")
        cmd = "printf '%s\\n' '#{escaped}' | sudo tee -a #{PATH} > /dev/null"
        run!(cmd)
      end

      def remove(ssh_principal:)
        # Rewrite the file atomically through a tmp file, then `sudo cp` it
        # back so the destination keeps root ownership. Principals are
        # server-generated and only contain [a-z0-9-], so stripping single
        # quotes is sufficient sanitization.
        safe = ssh_principal.to_s.gsub("'", "")
        cmd = "tmp=$(mktemp) && grep -v '#{safe}' #{PATH} > $tmp && sudo cp $tmp #{PATH} && rm $tmp"
        run!(cmd)
      end

      private

      def build_line(principal, pubkey, db_host, db_port)
        opts = [
          %(command="#{FORCE_COMMAND}"),
          "no-pty", "no-agent-forwarding", "no-X11-forwarding", "no-user-rc",
          %(permitopen="#{db_host}:#{db_port}"),
          %(environment="WOKKU_DEV_SESSION=#{principal}")
        ].join(",")
        cleaned = pubkey.to_s.strip.gsub(/\s+/, " ")
        "#{opts} #{cleaned}"
      end

      def run!(cmd)
        Hosts::Ssh.new(@app.server).run_raw(cmd)
      rescue Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError => e
        raise Apps::DevSession::Error.new(message_from(e), code: :ssh_error)
      end

      def message_from(e)
        e.respond_to?(:stderr) && e.stderr.present? ? e.stderr : e.message
      end
    end
  end
end
