module Webhooks
  class BitbucketController < ActionController::API
    before_action :verify_signature!

    def create
      event = request.headers["X-Event-Key"]

      case event
      when "repo:push"
        handle_push(JSON.parse(@payload))
      when "pullrequest:created", "pullrequest:updated"
        handle_pull_request_open(JSON.parse(@payload))
      when "pullrequest:fulfilled"
        handle_pull_request_fulfilled(JSON.parse(@payload))
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

    def handle_pull_request_open(payload)
      pr_id = payload.dig("pullrequest", "id")
      repo_full_name = payload.dig("repository", "full_name")
      branch = payload.dig("pullrequest", "source", "branch", "name")
      commit_sha = payload.dig("pullrequest", "source", "commit", "hash")
      pr_title = payload.dig("pullrequest", "title")

      return head :ok unless repo_full_name && pr_id

      parent_apps = AppRecord.where(git_provider: "bitbucket", git_repo_full_name: repo_full_name)
      return head :ok unless parent_apps.any?

      parent_apps.each do |parent_app|
        PrPreviewDeployJob.perform_later(
          parent_app_id: parent_app.id,
          pr_number: pr_id,
          branch: branch,
          commit_sha: commit_sha,
          pr_title: pr_title,
          repo_full_name: repo_full_name
        )
      end

      head :ok
    end

    def handle_pull_request_fulfilled(payload)
      pr_id = payload.dig("pullrequest", "id")
      repo_full_name = payload.dig("repository", "full_name")

      return head :ok unless repo_full_name && pr_id

      parent_apps = AppRecord.where(git_provider: "bitbucket", git_repo_full_name: repo_full_name)
      return head :ok unless parent_apps.any?

      parent_apps.each do |parent_app|
        PrPreviewCleanupJob.perform_later(
          parent_app_id: parent_app.id,
          pr_number: pr_id
        )
      end

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
