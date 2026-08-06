module Apps
  module Lifecycle
    # wokkud-native clone (W7 Phase 3, replaced the dokku clone wire). Creates the
    # new AppRecord fully flagged (born dokku-free, W2), copies the source's
    # EnvVar rows and bare git repo (so the clone is pushable), and — unless
    # skip_deploy — converges the source's current image into a running
    # new-name stack. skip_deploy: true (the default, dokku-parity) leaves
    # the clone created-but-not-running until its first push.
    class Cloner
      NAME_REGEX = Apps::Lifecycle::Renamer::NAME_REGEX

      def initialize(source, user:)
        @source = source
        @user   = user
      end

      def call!(new_name, skip_deploy: true)
        new_name = new_name.to_s.strip

        unless new_name.match?(NAME_REGEX)
          raise Apps::Lifecycle::Error.new("Invalid app name (lowercase letters, digits, hyphens; 2-50 chars)", code: :invalid_name)
        end

        if AppRecord.where(server_id: @source.server_id, name: new_name).exists?
          raise Apps::Lifecycle::Error.new("Name already taken on this server", code: :name_taken)
        end

        new_app = nil
        ActiveRecord::Base.transaction do
          new_app = AppRecord.create!(
            name: new_name,
            server: @source.server,
            team: @source.team,
            created_by_id: @user.id,
            deploy_branch: @source.deploy_branch,
            container_port: @source.container_port,
            wokkud_native: true, wokkud_routed: true,
            wokkud_git: true, wokkud_lifecycle: true
          )
          @source.env_vars.find_each do |ev|
            new_app.env_vars.create!(key: ev.key, value: ev.value)
          end
        end

        clone_bare_repo(new_app)
        unless skip_deploy
          begin
            converge_from_source!(new_app)
          rescue Apps::Lifecycle::Error
            # Old-contract parity: a failed clone leaves nothing behind (a
            # retry with the same name must not hit "name taken").
            begin
              Git::BareRepo.new(new_app.name).remove!
            rescue StandardError
              nil
            end
            new_app.destroy
            raise
          end
        end
        upsert_dns(new_name)
        new_app
      end

      private

      # Deploy the clone from the source's current image — same fallback
      # chain Lifecycle::Ops.converge! uses for the source itself: a
      # wokkud-built succeeded Deploy (image + Procfile commands + bash -l
      # wrap all ride via deploy:), else the source's last succeeded
      # stack.converge op params (adopted apps). No usable image = the
      # source was never deployed; fail with the lifecycle error contract.
      def converge_from_source!(new_app)
        src_deploy = @source.deploys.where(status: :succeeded).order(created_at: :desc).first
        if src_deploy&.builder == "wokkud"
          ::Lifecycle::Ops.converge!(new_app, deploy: src_deploy)
        else
          prev = @source.lifecycle_ops.succeeded.where(kind: "stack.converge").order(:created_at).last
          image = ::Lifecycle::Ops.image_ref_from(prev&.params)
          if image.blank?
            raise Apps::Lifecycle::Error.new("Source app has no deployable image — deploy #{@source.name} first or clone with skip_deploy", code: :invalid)
          end
          ::Lifecycle::Ops.converge!(new_app, image_ref: image,
                                     formation_commands: ::Lifecycle::Ops.formation_commands_from(prev.params))
        end
      rescue Apps::Lifecycle::Error
        raise
      rescue StandardError => e
        raise Apps::Lifecycle::Error.new("Clone created but failed to start: #{e.message}", code: :dokku_error)
      end

      # Fresh bare repo via ensure! (post-receive hook + receive config),
      # then copy every ref from the source repo — local-to-local through
      # the same WOKKU_GIT_REPO_ROOT paths Git::BareRepo owns. Best-effort:
      # a clone without history is still pushable.
      def clone_bare_repo(new_app)
        src = Git::BareRepo.new(@source.name)
        return unless src.exists?

        dst = Git::BareRepo.new(new_app.name).ensure!
        system("git", "-C", dst.path, "fetch", "--quiet", src.path, "+refs/*:refs/*", exception: true)
      rescue StandardError => e
        Rails.logger.warn("Cloner: bare repo copy #{@source.name} → #{new_app.name} failed: #{e.message}")
      end

      def upsert_dns(name)
        Wokku.config.dns_provider.create_app_record(name, @source.server.host)
      rescue StandardError => e
        Sentry.capture_exception(e, extra: { source_app_id: @source.id, new_name: name, action: "clone_dns" }) if defined?(Sentry)
      end
    end
  end
end
