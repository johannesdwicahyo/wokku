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
      action = payload["action"] # opened, synchronize, closed, reopened
      pr_number = payload.dig("pull_request", "number")
      repo_full_name = payload.dig("repository", "full_name")
      branch = payload.dig("pull_request", "head", "ref")
      commit_sha = payload.dig("pull_request", "head", "sha")
      pr_title = payload.dig("pull_request", "title")

      return head :ok unless repo_full_name && pr_number

      # Find parent apps connected to this repo
      parent_apps = AppRecord.where(github_repo_full_name: repo_full_name)
      return head :ok unless parent_apps.any?

      case action
      when "opened", "reopened", "synchronize"
        parent_apps.each do |parent_app|
          PrPreviewDeployJob.perform_later(
            parent_app_id: parent_app.id,
            pr_number: pr_number,
            branch: branch,
            commit_sha: commit_sha,
            pr_title: pr_title,
            repo_full_name: repo_full_name
          )
        end
      when "closed"
        parent_apps.each do |parent_app|
          PrPreviewCleanupJob.perform_later(
            parent_app_id: parent_app.id,
            pr_number: pr_number
          )
        end
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
