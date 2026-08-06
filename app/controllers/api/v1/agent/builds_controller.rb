module Api
  module V1
    module Agent
      # wokkud build-executor endpoints (Track A Phase 4c). Same trust
      # boundary as heartbeats: per-server ingest_token. Scoping is strict —
      # only this server's wokkud-builder deploys resolve at all (404
      # otherwise), a terminal deploy is 410 (the TarballDeployJob already
      # gave up; a late report must not touch it), and a second claim is 409
      # so a raced duplicate agent never double-builds.
      class BuildsController < BaseController
        BUILD_TIMEOUT_SECONDS = 600
        # Mirrors the Go producer's Procfile cap (wokkud parses ≤16KB into a
        # flat map[string]string) — anything bigger or differently shaped
        # didn't come from that producer.
        MAX_FORMATION_BYTES = 16 * 1024

        before_action :set_deploy

        def claim
          # Presign BEFORE stamping the claim: if the presign raises, the
          # claim is never consumed, so the job's fallback can still pick
          # this deploy up. builder: "wokkud" in the WHERE closes the
          # window where the job's 35s fallback clears builder between
          # set_deploy's read and this write — a raced claim loses (409)
          # instead of double-building.
          archive_url = Wokku.config.backup_store.presigned_get(@deploy.archive_key)
          # Local store can't presign — serve the archive ourselves behind
          # a short-lived signed token. request.base_url is by definition
          # reachable from the agent (it's the URL this claim came in on).
          if archive_url.nil? && @deploy.archive_key.present?
            token = Rails.application.message_verifier(:deploy_archive)
                         .generate(@deploy.id, expires_in: BUILD_TIMEOUT_SECONDS + 300)
            archive_url = "#{request.base_url}/api/v1/agent/archive?token=#{CGI.escape(token)}"
          end
          claimed = Deploy.where(id: @deploy.id, build_picked_up_at: nil, builder: "wokkud")
                          .update_all(build_picked_up_at: Time.current) == 1
          return head :conflict unless claimed

          append_log_line("\u2192 build claimed by #{@server.name} \u2014 downloading source\u2026\n")

          render json: {
            app_name: @deploy.app_record.name,
            archive_url: archive_url,
            push_ref: @deploy.wokkud_image_ref,
            timeout_seconds: BUILD_TIMEOUT_SECONDS
          }
        end

        def log
          chunk = params[:chunk].to_s
          return head :bad_request if chunk.empty?

          # Atomic SQL append — avoids a read-modify-write race with the
          # job's own log writes and an O(n^2) full-column re-read per chunk.
          Deploy.where(id: @deploy.id).update_all([ "log = COALESCE(log, '') || ?", chunk ])
          DeployChannel.broadcast_to(@deploy, { type: "log", data: chunk })
          head :ok
        end

        def report
          # Write build_finished_at and formation_json in ONE update! so the
          # converge (which the deploy job fires the moment build_finished_at
          # appears) can never read a finished build whose formation_json
          # hasn't landed yet. Older wokkud builds omit `formation` entirely —
          # leave formation_json untouched (nil) rather than clobbering it.
          attrs = {
            build_finished_at: Time.current,
            build_error: params[:status] == "succeeded" ? nil : (params[:error].presence || "build failed")
          }
          attrs[:formation_json] = valid_formation if valid_formation
          @deploy.update!(attrs)

          # Close the log with an unambiguous trailer — raw build output
          # ends mid-push otherwise and reads as "did it finish?".
          if params[:status] == "succeeded"
            host = @deploy.app_record.domains.order(:created_at).first&.hostname
            append_log_line("\n\u2192 build succeeded \u2014 deploying#{host ? " \u00b7 live shortly at https://#{host}" : ""}\n")
          else
            append_log_line("\n\u2717 build failed: #{attrs[:build_error]}\n")
          end
          head :ok
        end

        private

        # Milestone lines the CONTROL PLANE narrates into the build log
        # (claim, trailer) — same append+broadcast path as agent chunks.
        def append_log_line(line)
          Deploy.where(id: @deploy.id).update_all([ "log = COALESCE(log, '') || ?", line ])
          DeployChannel.broadcast_to(@deploy, { type: "log", data: line })
        end

        # Only a flat { proc => command_string } hash within the Go
        # producer's size cap is trustworthy — anything else (array, nested
        # hash, oversized) is silently skipped so a malformed formation
        # payload never fails an otherwise-good build report; converge just
        # falls back to image CMD.
        def valid_formation
          formation = params[:formation]
          return nil unless formation.present?
          return nil unless formation.is_a?(ActionController::Parameters)

          hash = formation.to_unsafe_h
          unless hash.is_a?(Hash) && hash.values.all? { |v| v.is_a?(String) } && hash.to_s.bytesize <= MAX_FORMATION_BYTES
            Rails.logger.warn("deploy=#{@deploy.id} rejected malformed formation payload")
            return nil
          end

          hash
        end

        def set_deploy
          @deploy = Deploy.joins(:app_record)
                          .where(app_records: { server_id: @server.id }, builder: "wokkud")
                          .find_by(id: params[:id])
          return head :not_found unless @deploy

          head :gone if @deploy.status.in?(%w[succeeded failed timed_out])
        end
      end
    end
  end
end
