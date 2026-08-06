module Webhooks
  class GithubController < ActionController::API
    before_action :verify_signature!

    def create
      event = request.headers["X-GitHub-Event"]

      case event
      when "push"
        handle_push(JSON.parse(@payload))
      when "pull_request"
        handle_pull_request(JSON.parse(@payload))
      when "ping"
        head :ok
      else
        head :ok
      end
    end

    private

    def handle_push(payload)
      ref = payload["ref"]
      branch = ref&.sub("refs/heads/", "")
      repo_full_name = payload.dig("repository", "full_name")
      commit_sha = payload.dig("head_commit", "id")
      commit_message = payload.dig("head_commit", "message")

      return head :ok unless repo_full_name && branch

      apps = AppRecord.where(github_repo_full_name: repo_full_name, deploy_branch: branch)
                      .includes(:server)

      apps.find_each do |app|
        # Skip apps whose server is unreachable to avoid creating orphaned
        # "pending" deploys that never resolve.
        unless app.server && app.server.connected?
          Rails.logger.warn(
            "GitHub webhook: skipping deploy for #{app.name} — server #{app.server&.name || '(none)'} not connected (status: #{app.server&.status || 'missing'})"
          )
          next
        end

        deploy = app.deploys.create!(
          status: :pending,
          commit_sha: commit_sha
        )
        release = app.releases.create!(
          version: (app.releases.maximum(:version) || 0) + 1,
          deploy: deploy,
          description: commit_message&.truncate(200)
        )

        GithubDeployJob.perform_later(
          app_id: app.id,
          deploy_id: deploy.id,
          repo_full_name: repo_full_name,
          branch: branch,
          commit_sha: commit_sha
        )
      end

      head :ok
    end

    def handle_pull_request(payload)
      event = Preview::Provider::GitHub.parse(payload)
      Preview::EventDispatcher.handle(event)
      head :ok
    end

    def verify_signature!
      request.body.rewind
      @payload = request.body.read
      signature = request.headers["X-Hub-Signature-256"]

      unless GithubApp.verify_webhook_signature(@payload, signature)
        head :unauthorized
      end
    end
  end
end
