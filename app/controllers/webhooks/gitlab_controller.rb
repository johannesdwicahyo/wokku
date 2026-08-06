module Webhooks
  class GitlabController < ActionController::API
    before_action :verify_token!

    def create
      event = request.headers["X-Gitlab-Event"]

      case event
      when "Push Hook"
        handle_push(JSON.parse(@payload))
      when "Merge Request Hook"
        handle_merge_request(JSON.parse(@payload))
      else
        head :ok
      end
    end

    private

    def handle_push(payload)
      ref = payload["ref"]
      branch = ref&.sub("refs/heads/", "")
      repo_full_name = payload.dig("project", "path_with_namespace")
      commit_sha = payload["checkout_sha"]
      commit_message = payload.dig("commits", 0, "message")

      return head :ok unless repo_full_name && branch

      apps = AppRecord.where(git_provider: "gitlab", git_repo_full_name: repo_full_name, deploy_branch: branch)

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

        GitlabDeployJob.perform_later(
          app_id: app.id,
          deploy_id: deploy.id,
          repo_full_name: repo_full_name,
          branch: branch,
          commit_sha: commit_sha
        )
      end

      head :ok
    end

    def handle_merge_request(payload)
      event = Preview::Provider::Gitlab.parse(payload)
      Preview::EventDispatcher.handle(event)
      head :ok
    end

    def verify_token!
      request.body.rewind
      @payload = request.body.read
      token = request.headers["X-Gitlab-Token"]
      expected = ENV["GITLAB_WEBHOOK_SECRET"].presence

      # Per-app secret: find app by repo and check its secret
      # Fall back to global env secret
      unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected.to_s)
        head :unauthorized
      end
    end
  end
end
