require "shellwords"

module Apps
  module DevSession
    class AuthorizedKeysWriter
      PATH = "/etc/wokku/dev-session-authorized-keys".freeze
      FORCE_COMMAND = "/opt/wokku/bin/wokku-dev-shell".freeze
      HELPER = "/usr/local/sbin/wokku-dev-keys".freeze

      def initialize(app)
        @app = app
      end

      def append(ssh_principal:, user_pubkey:, db_remote_host:, db_remote_port:)
        line = build_line(ssh_principal, user_pubkey, db_remote_host, db_remote_port)
        # PATH is root-owned (sshd StrictModes). Root appends directly; a
        # non-root host user pipes the line to the wokku-dev-keys helper,
        # which validates it against build_line's exact option prefix.
        if Hosts::Ssh.root_user?
          # Escape single quotes for safe single-quoted shell interpolation.
          escaped = line.gsub("'", "'\\\\''")
          run!("printf '%s\\n' '#{escaped}' | sudo tee -a #{PATH} > /dev/null")
        else
          run!("sudo -n #{HELPER} add", stdin: "#{line}\n")
        end
      end

      def remove(ssh_principal:)
        if Hosts::Ssh.root_user?
          # Rewrite through a tmp file, then cp back so PATH keeps root
          # ownership. Principals are server-generated [a-z0-9-], so
          # stripping single quotes is sufficient sanitization.
          safe = ssh_principal.to_s.gsub("'", "")
          run!("tmp=$(mktemp) && grep -v '#{safe}' #{PATH} > $tmp && sudo cp $tmp #{PATH} && rm $tmp")
        else
          run!("sudo -n #{HELPER} remove #{Shellwords.escape(ssh_principal.to_s)}")
        end
      end

      private

      # Option order is load-bearing: the host helper matches this exact prefix.
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

      def run!(cmd, **opts)
        Hosts::Ssh.new(@app.server).run_raw(cmd, **opts)
      rescue Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError => e
        raise Apps::DevSession::Error.new(message_from(e), code: :ssh_error)
      end

      def message_from(e)
        e.respond_to?(:stderr) && e.stderr.present? ? e.stderr : e.message
      end
    end
  end
end
