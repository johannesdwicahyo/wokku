module Webhooks
  class BitbucketController < ActionController::API
    before_action :verify_signature!

    def create
      event = request.headers["X-Event-Key"]

      case event
      when "repo:push"
        handle_push(JSON.parse(@payload))
      when "pullrequest:created", "pullrequest:updated", "pullrequest:fulfilled", "pullrequest:rejected"
        handle_pull_request(JSON.parse(@payload), event)
      else
        head :ok
      end
    end

    private

    def handle_push(payload)
      repo_full_name = payload.dig("repository", "full_name")
      push_changes = payload.dig("push", "changes") || []

      return head :ok unless repo_full_name

      push_changes.each do |change|
        branch = change.dig("new", "name")
        commit_sha = change.dig("new", "target", "hash")
        commit_message = change.dig("new", "target", "message")
        next unless branch

        apps = AppRecord.where(git_provider: "bitbucket", git_repo_full_name: repo_full_name, deploy_branch: branch)

        apps.find_each do |app|
          deploy = app.deploys.create!(
            status: :pending,
            commit_sha: commit_sha
          )
          release = app.releases.create!(
            version: (app.releases.maximum(:version) || 0) + 1,
            deploy: deploy,
            description: commit_message&.truncate(200)
          )

          BitbucketDeployJob.perform_later(
            app_id: app.id,
            deploy_id: deploy.id,
            repo_full_name: repo_full_name,
            branch: branch,
            commit_sha: commit_sha
          )
        end
      end

      head :ok
    end

    def handle_pull_request(payload, event_key)
      event = Preview::Provider::Bitbucket.parse(payload, event_key: event_key)
      Preview::EventDispatcher.handle(event)
      head :ok
    end

    def verify_signature!
      request.body.rewind
      @payload = request.body.read
      signature = request.headers["X-Hub-Signature"]
      secret = ENV["BITBUCKET_WEBHOOK_SECRET"].presence

      unless secret.present? && signature.present?
        head :unauthorized
        return
      end

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, @payload)
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
        head :unauthorized
      end
    end
  end
end
