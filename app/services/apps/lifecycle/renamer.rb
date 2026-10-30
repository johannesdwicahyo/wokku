module Apps
  module Lifecycle
    # wokkud-native rename (W7 Phase 3, replaced the dokku rename wire). Ordering is
    # the safety contract — a mid-failure must leave the app SERVING:
    #
    #   1. Rename control-plane rows (app + canonical Domain) in one txn.
    #      The old Swarm services are untouched and keep serving.
    #   2. Converge the new-name services on a FRESH swarm port (the old web
    #      service still publishes the old one — Swarm ingress ports are
    #      cluster-unique). Any failure rolls the rows back and raises loud:
    #      the old stack never stopped, the app never went down.
    #   3. Only after the new stack is verified up (converge! waits for the
    #      op to succeed): remove the old-name services and clean up legacy
    #      Domain rows, bare repo, DNS — all best-effort, never blocking.
    #
    # Registry note: old deploys' image refs keep the wokku/<old-name> repo
    # name; rollback rows are left alone on purpose — those tags still exist
    # and remain rollback-able, they just live under the old repo name.
    class Renamer
      NAME_REGEX = /\A[a-z0-9][a-z0-9-]{1,49}\z/

      def initialize(app)
        @app = app
      end

      def call!(new_name)
        new_name = new_name.to_s.strip
        return @app if new_name == @app.name

        unless new_name.match?(NAME_REGEX)
          raise Apps::Lifecycle::Error.new("Invalid app name (lowercase letters, digits, hyphens; 2-50 chars)", code: :invalid_name)
        end

        if AppRecord.where(server_id: @app.server_id, name: new_name).where.not(id: @app.id).exists?
          raise Apps::Lifecycle::Error.new("Name already taken on this server", code: :name_taken)
        end

        old_name = @app.name
        old_port = @app.swarm_port
        # Resolved BEFORE the row rename: Deploy#wokkud_image_ref derives the
        # registry repo from the app's CURRENT name, and the pushed tags live
        # under wokku/<old-name> — resolving after the rename would point the
        # converge at a repo that doesn't exist. blank = never deployed =
        # nothing running = no swarm dance needed.
        image_ref = current_image_ref if @app.wokkud_lifecycle?

        rename_rows!(old_name, new_name)

        if @app.wokkud_lifecycle? && image_ref.present?
          begin
            # Fresh port for the new-name web service; the old one still
            # holds old_port until it's removed below.
            @app.update!(swarm_port: nil)
            # A stopped/sleeping app keeps its process_scales, so a plain
            # converge would boot it under the new name.
            idle = (@app.stopped? || @app.sleeping?) ? { formation: ::Lifecycle::Ops.stop_formation(@app), allow_empty: true } : {}
            ::Lifecycle::Ops.converge!(@app, image_ref: image_ref, **idle)
          rescue StandardError => e
            # Abort loud: roll the rows back — the old services never
            # stopped, so the app is still serving under the old name.
            # swarm_port unconditionally back to old_port: converge! may have
            # allocated a fresh one, and Caddy must keep dialing the port the
            # old (still-running) web service publishes.
            @app.update!(swarm_port: old_port)
            rename_rows!(new_name, old_name)
            raise Apps::Lifecycle::Error.new("Rename aborted, app unchanged — new stack failed to start: #{e.message}", code: :dokku_error)
          end
          remove_old_swarm_stack(old_name, new_name)
        end

        cleanup_legacy_domains(old_name)
        move_bare_repo(old_name, new_name)
        reshuffle_dns(old_name, new_name)
        @app
      end

      private

      # Same fallback chain Lifecycle::Ops.converge! uses: last succeeded
      # wokkud-built Deploy, else the last succeeded stack.converge op's
      # persisted image_ref (adopted apps). Op params store the literal ref
      # string, so both paths yield a wokku/<old-name> ref that really exists.
      def current_image_ref
        deploy = @app.deploys.where(status: :succeeded).order(created_at: :desc).first
        ref = deploy&.wokkud_image_ref if deploy&.builder == "wokkud"
        ref || ::Lifecycle::Ops.image_ref_from(
          @app.lifecycle_ops.succeeded.where(kind: "stack.converge").order(:created_at).last&.params
        )
      end

      # App row + canonical Domain row flip together: Routers::ConfigBuilder
      # reads both, so Caddy always sees a consistent name/hostname pair.
      # EnvVar rows (and every other FK child) ride the app untouched.
      def rename_rows!(from, to)
        zone = Wokku.config.canonical_domain
        ActiveRecord::Base.transaction do
          @app.update!(name: to)
          if (domain = @app.domains.find_by(hostname: "#{from}.#{zone}"))
            domain.update!(hostname: "#{to}.#{zone}")
          end
        end
      end

      # stack.remove resolves the app name at CLAIM time from the app row
      # (agent lifecycle_ops claim endpoint), so old-name services can only
      # be targeted while the row briefly bears the old name again.
      # ponytail: name-flip window means a router heartbeat landing in these
      # few seconds re-renders the old name for one beat; upgrade path is an
      # explicit app-name param on stack.remove once the agent floor allows.
      # Failure never aborts — the new stack is serving; orphaned old
      # services are operator-prunable (they hold old swarm_port + RAM).
      def remove_old_swarm_stack(old_name, new_name)
        @app.update_column(:name, old_name)
        ::Lifecycle::Ops.remove!(@app, wait: true)
      rescue StandardError => e
        # A still-PENDING remove op must not outlive the name flip: claimed
        # after the ensure below it would resolve to the NEW name and tear
        # down the stack we just brought up. Seal it (terminal ops 410 the
        # agent's claim). A CLAIMED op already carries the old name — safe.
        @app.lifecycle_ops.where(kind: "stack.remove", status: :pending).find_each do |op|
          op.update!(status: :failed, error: "sealed by Renamer: rename completed before claim", finished_at: Time.current)
        end
        Rails.logger.warn("Renamer: old swarm stack #{old_name} not removed (prune manually): #{e.message}")
      ensure
        @app.update_column(:name, new_name)
      end

      # Non-canonical managed rows (legacy wokku.cloud) aren't renamed: their
      # DNS record is deleted below and never recreated, so a renamed row
      # would advertise a dead vhost. Custom-domain rows are untouched.
      def cleanup_legacy_domains(old_name)
        (Wokku.config.owned_domains - [ Wokku.config.canonical_domain ]).each do |zone|
          @app.domains.find_by(hostname: "#{old_name}.#{zone}")&.destroy
        end
      rescue StandardError => e
        Rails.logger.warn("Renamer: legacy domain cleanup for #{old_name} failed: #{e.message}")
      end

      # History rides to the new name (the B2 rename-orphaned-bare-repo fix)
      # AND the freed old path is gone, so whoever claims the old name next
      # can't clone the previous tenant's history. Never blocks the rename.
      def move_bare_repo(old_name, new_name)
        old_repo = Git::BareRepo.new(old_name)
        return unless old_repo.exists?

        new_repo = Git::BareRepo.new(new_name)
        if new_repo.exists?
          old_repo.remove!
        else
          FileUtils.mkdir_p(File.dirname(new_repo.path))
          FileUtils.mv(old_repo.path, new_repo.path)
        end
      rescue StandardError => e
        Rails.logger.warn("Renamer: failed to move bare git repo #{old_name} → #{new_name}: #{e.message}")
      end

      def reshuffle_dns(old_name, new_name)
        # New name → canonical zone only. Old name → every zone, since the
        # app may have a legacy wokku.cloud record from before any cutover.
        Wokku.config.dns_provider.create_app_record(new_name, @app.server.host)
        Wokku.config.dns_provider.delete_app_record(old_name)
      rescue StandardError => e
        Sentry.capture_exception(e, extra: { app_id: @app.id, action: "rename_dns" }) if defined?(Sentry)
      end
    end
  end
end
