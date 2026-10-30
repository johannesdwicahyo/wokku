require "shellwords"

module Preview
  class Deployer
    # "#{parent}-pr-#{n}" can exceed Git::BareRepo::NAME_RE's 63-char cap for a
    # long parent name — fail the deploy cleanly instead of an unhandled
    # ArgumentError from BareRepo.new.
    class NameTooLong < StandardError; end

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
        write_env(preview)
        Preview::DnsRegistrar.new(preview).register
        # Previews deploy with the parent's env and NO databases (zero preview
        # usage to date). Per-preview DBs return as wokkud shared tenants if
        # previews get real usage — never as dokku services (W7).

        # Build synchronously through the shared native path. Previews own
        # their own completion (PR comment, preview DNS, status) so they do
        # NOT hand off to TarballDeployJob's async/generic tail.
        log = build!(preview, deploy)

        deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
        preview.update!(status: :running, last_commit_sha: @event.sha, last_commit_at: Time.current)
        Preview::Commenter.new(preview).deployed!(url: "https://#{preview.preview_hostname}", commit_sha: @event.sha)
      rescue Timeout::Error
        deploy.update!(status: :timed_out, finished_at: Time.current)
        preview.update!(status: :crashed)
      rescue Deploys::BuildAndConverge::Error, NameTooLong => e
        deploy.update!(status: :failed, finished_at: Time.current, log: e.message)
        preview.update!(status: :crashed)
      end

      preview
    end

    private

    # Fetch the PR head into the preview's own bare repo (the same pattern
    # GithubDeployJob/TemplateDeployer use for wokkud_git apps), archive+upload
    # it so the wokkud build agent has an archive to claim, then build+converge
    # synchronously. Returns the build log.
    def build!(preview, deploy)
      unless preview.name.match?(Git::BareRepo::NAME_RE)
        raise NameTooLong, "preview app name #{preview.name.inspect} exceeds the 63-char git-repo limit"
      end

      repo = Git::BareRepo.new(preview.name)
      repo.ensure!
      begin
        # Private repos need the installation token (same as GithubDeployJob).
        token = GithubApp.new(@event.installation_id).access_token if @event.installation_id && GithubApp.configured?
        GithubDeployJob.system_fetch(repo, "https://github.com/#{@event.repo_full_name}.git", @event.branch, token: token)
      rescue RuntimeError => e
        # system(..., exception: true) raises a raw RuntimeError on a failed
        # fetch (network error, auth failure, private/nonexistent repo) —
        # re-raise as the type #call's rescue already handles so it lands in
        # the same terminal failed/crashed path instead of wedging the
        # preview in :building forever.
        raise Deploys::BuildAndConverge::Error, "github fetch failed: #{e.message}"
      end
      # PushDeployer hex-validates the sha, so resolve the ref we just fetched
      # rather than passing the branch name.
      sha = resolve_sha(repo, @event.branch)
      begin
        deploy.update!(archive_key: Git::PushDeployer.archive_and_upload(preview, sha))
      rescue Git::PushDeployer::Error => e
        raise Deploys::BuildAndConverge::Error, e.message
      end
      Deploys::BuildAndConverge.call(app: preview, deploy: deploy)
    end

    def resolve_sha(repo, branch)
      sha = `git -C #{Shellwords.escape(repo.path)} rev-parse refs/heads/#{Shellwords.escape(branch)}`.strip
      raise Deploys::BuildAndConverge::Error, "could not resolve #{branch} after fetch" unless sha.match?(/\A[0-9a-f]{40}\z/)
      sha
    end

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
        wokkud_native: true, wokkud_routed: true,
        wokkud_git: true, wokkud_lifecycle: true,
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

    def write_env(preview)
      env = Preview::EnvBuilder.new(@parent).build
      Apps::EnvWriter.set(preview, env) if env.any?
    end
  end
end
