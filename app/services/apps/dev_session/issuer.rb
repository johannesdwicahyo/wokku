module Apps
  module DevSession
    class Issuer
      MAX_DURATION_MIN = 120
      DEFAULT_DURATION_MIN = 30

      def initialize(app:, user:)
        @app  = app
        @user = user
      end

      def call!(duration_min: DEFAULT_DURATION_MIN)
        db = @app.primary_database
        if db.nil? || db.service_type != "postgres"
          raise Apps::DevSession::Error.new("App has no Postgres database linked", code: :no_postgres)
        end

        pubkey = @user.ssh_public_keys.first&.public_key
        if pubkey.blank?
          raise Apps::DevSession::Error.new("Add an SSH key with `wokku ssh-keys:add` first", code: :no_ssh_key)
        end

        capped = [ duration_min.to_i, MAX_DURATION_MIN ].min
        capped = DEFAULT_DURATION_MIN if capped <= 0
        principal = "dev-session-#{SecureRandom.uuid}"
        container_name = "dokku.#{db.service_type}.#{db.name}"
        # sshd's permitopen can't resolve docker container hostnames from the
        # host's network namespace — it needs an IP literal. Resolve the
        # container's bridge IP now and store THAT in db_remote_host so the
        # authorized_keys line constrains the tunnel to a routable address.
        ip = resolve_container_ip(container_name)
        if ip.blank?
          raise Apps::DevSession::Error.new("Could not resolve IP for #{container_name}", code: :container_not_found)
        end
        db_remote_host = ip

        session = ::DevSession.create!(
          user: @user,
          app_record: @app,
          ssh_principal: principal,
          db_remote_host: db_remote_host,
          db_remote_port: 5432,
          read_only: true,
          expires_at: capped.minutes.from_now
        )

        Apps::DevSession::AuthorizedKeysWriter.new(@app).append(
          ssh_principal: principal,
          user_pubkey: pubkey,
          db_remote_host: db_remote_host,
          db_remote_port: 5432
        )

        session
      end

      private

      def resolve_container_ip(container_name)
        ssh = ::Hosts::Ssh.new(@app.server)
        out = ssh.run_raw("docker inspect #{container_name} --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{println}}{{end}}'")
        out.to_s.lines.map(&:strip).reject(&:empty?).first
      rescue ::Hosts::Ssh::CommandError, ::Hosts::Ssh::ConnectionError
        nil
      end
    end
  end
end
