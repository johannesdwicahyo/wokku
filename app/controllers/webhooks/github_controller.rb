module Webhooks
  class GithubController < ActionController::API
    before_action :verify_signature!

    def create
      event = request.headers["X-GitHub-Event"]

      case event
      when "push"
        handle_push(JSON.parse(@payload))
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

      apps.find_each do |app|
        deploy = app.deploys.create!(
          status: :pending,
          commit_sha: commit_sha,
          description: "GitHub push: #{commit_message&.truncate(80)}"
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
