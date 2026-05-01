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
      action = payload.dig("object_attributes", "action") # open, reopen, update, merge, close
      mr_iid = payload.dig("object_attributes", "iid")
      repo_full_name = payload.dig("project", "path_with_namespace")
      branch = payload.dig("object_attributes", "source_branch")
      commit_sha = payload.dig("object_attributes", "last_commit", "id")
      mr_title = payload.dig("object_attributes", "title")

      return head :ok unless repo_full_name && mr_iid

      parent_apps = AppRecord.where(git_provider: "gitlab", git_repo_full_name: repo_full_name)
      return head :ok unless parent_apps.any?

      case action
      when "open", "reopen", "update"
        parent_apps.each do |parent_app|
          PrPreviewDeployJob.perform_later(
            parent_app_id: parent_app.id,
            pr_number: mr_iid,
            branch: branch,
            commit_sha: commit_sha,
            pr_title: mr_title,
            repo_full_name: repo_full_name
          )
        end
      when "close", "merge"
        parent_apps.each do |parent_app|
          PrPreviewCleanupJob.perform_later(
            parent_app_id: parent_app.id,
            pr_number: mr_iid
          )
        end
      end

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
