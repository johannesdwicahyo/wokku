module Preview
  class Deployer
    DEPLOY_TIMEOUT = 15.minutes

    def initialize(parent:, event:)
      @parent = parent
      @event  = event
    end

    def call
      preview = upsert_preview_record
      return preview if already_deployed_at_sha?(preview)

      deploy = preview.deploys.create!(status: :building, started_at: Time.current, commit_sha: @event.sha)
      DeployChannel.broadcast_to(deploy, type: "log", data: "Deploying PR ##{@event.pr_number} preview...\n")

      begin
        prepare_app(preview) if @new_app
        write_env(preview)
        Preview::DnsRegistrar.new(preview).register
        Preview::DatabaseProvisioner::Empty.new(preview).provision

        Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
          repo_url = "https://github.com/#{@event.repo_full_name}.git"
          client.run_streaming("git:sync --build #{preview.name} #{repo_url} #{@event.branch}") do |chunk|
            DeployChannel.broadcast_to(deploy, type: "log", data: chunk)
          end
        end

        deploy.update!(status: :succeeded, finished_at: Time.current)
        preview.update!(status: :running, last_commit_sha: @event.sha, last_commit_at: Time.current)
        Preview::Commenter.new(preview).deployed!(url: "https://#{preview.preview_hostname}", commit_sha: @event.sha)
      rescue Timeout::Error
        deploy.update!(status: :timed_out, finished_at: Time.current)
        preview.update!(status: :crashed)
      rescue Dokku::Client::CommandError => e
        deploy.update!(status: :failed, finished_at: Time.current, log: e.message)
        preview.update!(status: :crashed)
      end

      preview
    end

    private

    def upsert_preview_record
      preview = @parent.preview_apps.find_or_initialize_by(pr_number: @event.pr_number)
      @new_app = preview.new_record?

      preview.assign_attributes(
        team: @parent.team,
        creator: @parent.creator,
        server: @parent.server,
        name: "#{@parent.name}-pr-#{@event.pr_number}",
        is_preview: true,
        billing_exempt: true,
        deploy_branch: @event.branch,
        git_repository_url: "https://github.com/#{@event.repo_full_name}.git",
        github_repo_full_name: nil,
        status: :deploying,
        last_commit_sha: @event.sha,
        last_commit_at: Time.current
      )
      preview.save!
      preview
    end

    def already_deployed_at_sha?(preview)
      return false if @new_app
      preview.deploys
             .where(commit_sha: @event.sha, status: %i[building succeeded])
             .exists?
    end

    def prepare_app(preview)
      Dokku::Apps.new(client).create(preview.name)
    end

    def write_env(preview)
      env = Preview::EnvBuilder.new(@parent).build
      Dokku::Config.new(client).set(preview.name, env) if env.any?
    end

    def client
      @client ||= Dokku::Client.new(@parent.server)
    end
  end
end
