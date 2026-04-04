class PrPreviewDeployJob < ApplicationJob
  queue_as :deploys

  DEPLOY_TIMEOUT = 15.minutes

  def perform(parent_app_id:, pr_number:, branch:, commit_sha:, pr_title:, repo_full_name:)
    parent_app = AppRecord.find(parent_app_id)
    server = parent_app.server
    client = Dokku::Client.new(server)

    preview_name = "#{parent_app.name}-pr-#{pr_number}"
    repo_url = "https://github.com/#{repo_full_name}.git"

    # Find or create preview app
    app = AppRecord.find_or_initialize_by(name: preview_name, server: server)
    is_new = app.new_record?

    app.assign_attributes(
      team: parent_app.team,
      creator: parent_app.creator,
      deploy_branch: branch,
      git_repository_url: repo_url,
      github_repo_full_name: nil, # Don't trigger webhooks for preview apps
      status: :deploying,
      is_preview: true,
      pr_number: pr_number,
      parent_app_id: parent_app.id
    )
    app.save!

    # Create deploy record
    deploy = app.deploys.create!(
      status: :building,
      started_at: Time.current,
      commit_sha: commit_sha
    )

    log = ""
    DeployChannel.broadcast_to(deploy, { type: "log", data: "Deploying PR ##{pr_number} preview...\n" })

    begin
      # Create Dokku app if new
      if is_new
        Dokku::Apps.new(client).create(preview_name)

        # Copy env vars from parent app (except domain-specific ones)
        parent_env = Dokku::Config.new(client).list(parent_app.name)
        preview_env = parent_env.except("DOKKU_PROXY_PORT", "DOKKU_PROXY_SSL_PORT")
        Dokku::Config.new(client).set(preview_name, preview_env) if preview_env.any?

        # Link same databases as parent
        parent_app.database_services.each do |db|
          begin
            Dokku::Databases.new(client).link(db.service_type, db.name, preview_name)
          rescue Dokku::Client::CommandError
            # Already linked or not available — skip
          end
        end
      end

      # Deploy the PR branch
      Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
        client.run_streaming("git:sync --build #{preview_name} #{repo_url} #{branch}") do |data|
          log << data
          DeployChannel.broadcast_to(deploy, { type: "log", data: data })
        end
      end

      deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
      app.update!(status: :running)

      # Get the preview URL
      domains = Dokku::Domains.new(client).list(preview_name) rescue []
      preview_url = domains.first ? "https://#{domains.first}" : "http://#{server.host}"

      # Comment on the PR with the preview URL
      comment_on_pr(parent_app, pr_number, preview_url, commit_sha)

      DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })

    rescue Timeout::Error
      deploy.update!(status: :timed_out, log: log + "\nDeploy timed out", finished_at: Time.current)
      app.update!(status: :crashed)
      DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
    rescue Dokku::Client::CommandError => e
      deploy.update!(status: :failed, log: log + "\n#{e.message}", finished_at: Time.current)
      app.update!(status: :crashed)
      DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    end
  end

  private

  def comment_on_pr(parent_app, pr_number, preview_url, commit_sha)
    user = User.find_by(github_installation_id: [ nil ].compact)
    # Find any user with a GitHub installation for this repo's owner
    user = User.where.not(github_installation_id: nil).first
    return unless user&.github_installation_id

    github = GithubApp.new(user.github_installation_id)
    body = "**Preview deployed!** :rocket:\n\n" \
           "| | |\n|---|---|\n" \
           "| **URL** | #{preview_url} |\n" \
           "| **Commit** | `#{commit_sha&.first(7)}` |\n" \
           "| **App** | `#{parent_app.name}-pr-#{pr_number}` |\n\n" \
           "_Deployed by [Wokku](https://wokku.dev)_"

    github.client.add_comment(
      parent_app.github_repo_full_name,
      pr_number,
      body
    )
  rescue => e
    Rails.logger.warn("PrPreviewDeployJob: Failed to comment on PR: #{e.message}")
  end
end
