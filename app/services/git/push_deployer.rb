module Git
  # Converges a received git push (or provider fetch) into the tarball
  # deploy pipeline: archive the sha from the app's bare repo, upload it,
  # create/reuse a Deploy, enqueue TarballDeployJob.
  class PushDeployer
    DEPLOYABLE_REFS = %w[refs/heads/main refs/heads/master].freeze
    # A git object name is always hex; validate before it reaches `git
    # archive` argv so a ref value starting with `-` can never smuggle a
    # flag (defense-in-depth — git supplies real shas, but the hook is a
    # trust boundary).
    SHA_RE = /\A[0-9a-f]{7,64}\z/
    # `git push wokku :main` (branch deletion) sends new-sha "0"*40 — all
    # hex, so it'd otherwise pass SHA_RE and fall through to a confusing
    # "could not archive 0000000" from a nonexistent object. Treat it as a
    # deletion notice instead: no Deploy row, friendly typed message.
    ZERO_SHA_RE = /\A0+\z/

    class Error < StandardError
      attr_reader :error_code
      def initialize(code, message)
        @error_code = code
        super(message)
      end
    end

    # Archive `sha` out of the app's bare repo and upload it to the deploy
    # archive store, returning the object key. Shared with Preview::Deployer,
    # which fetches a PR head into the preview's bare repo and needs the same
    # archive_key contract the wokkud build agent presigns. Creates no Deploy
    # row — the caller owns that.
    def self.archive_and_upload(app, sha)
      raise Error.new(:ref_not_deployable, "not a deployable commit") unless SHA_RE.match?(sha.to_s)

      key = "deploy-archives/#{app.id}/#{SecureRandom.uuid}.tar.gz"
      repo = BareRepo.new(app.name)
      Tempfile.create([ "push-archive", ".tar.gz" ]) do |tmp|
        Tempfile.create("push-archive-err") do |err|
          # `--` ends option parsing; sha is hex-validated above, so this is
          # belt-and-suspenders. stderr captured for ops debugging.
          ok = system("git", "-C", repo.path, "archive", "--format=tar.gz", "-o", tmp.path, "--", sha,
                      out: File::NULL, err: err.path)
          unless ok && File.size(tmp.path).positive?
            Rails.logger.warn("PushDeployer archive #{app.name} #{sha[0, 7]}: #{File.read(err.path).strip}")
            raise Error.new(:archive_failed, "could not archive #{sha[0, 7]} — retry the push")
          end
        end
        File.open(tmp.path, "rb") { |io| Wokku.config.backup_store.put(key, io) }
        system("git", "-C", repo.path, "gc", "--auto", "--quiet")
      end
      key
    end

    def initialize(app_record, sha:, ref:, deploy: nil)
      @app = app_record
      @sha = sha
      @ref = ref
      @deploy = deploy
    end

    def call
      if ZERO_SHA_RE.match?(@sha.to_s)
        raise Error.new(:ref_not_deployable, "branch deletion — nothing to deploy")
      end

      unless SHA_RE.match?(@sha.to_s)
        raise Error.new(:ref_not_deployable, "not a deployable commit")
      end

      unless @deploy
        unless DEPLOYABLE_REFS.include?(@ref)
          raise Error.new(:ref_not_deployable, "only main/master deploys; #{@ref} was stored but not deployed")
        end
        if @app.deploy_locked_at?
          raise Error.new(:app_locked, "deploys are locked for #{@app.name} — run `wokku unlock` to deploy")
        end
        if @app.deploys.where(status: [ :pending, :building ]).exists?
          raise Error.new(:deploy_in_progress, "a deploy is already in progress — wait for it or check `wokku deploys`")
        end
      end

      key = self.class.archive_and_upload(@app, @sha)

      deploy = @deploy || @app.deploys.create!(status: :pending)
      deploy.update!(commit_sha: @sha, archive_key: key)
      TarballDeployJob.perform_later(app_id: @app.id, deploy_id: deploy.id)
      deploy
    end
  end
end
