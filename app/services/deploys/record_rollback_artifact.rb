module Deploys
  # Shared "record this deploy as a rollback target, then prune stale
  # registry tags" unit. Every deploy success path calls this — TarballDeployJob,
  # DeployJob, GithubDeployJob, GitlabDeployJob, BitbucketDeployJob,
  # RollbackDeployJob's archive branch, and Git::DeployForwarder (git push)
  # — so a rollback target is recorded no matter which path built the app,
  # not just uploaded-tarball deploys (see Track A Phase 4a Task 4's plan
  # line: rollback images are tagged after every successful deploy, "this
  # path AND the existing ones").
  #
  # 2026-07-27 rewrite (rollback/registry family fix): every live deploy now
  # builds through wokkud, which already pushes `wokku/<app>:<deploy_id>` to
  # the registry as part of the build — no re-tagging, no separate push, no
  # `wokku-rollback/` namespace. `deploy.image_ref` is just set to that
  # existing tag (`Deploy#wokkud_image_ref`), and stale build tags are pruned
  # agent-side via a digest-aware `registry.prune` LifecycleOp (kills the
  # same-digest delete-collision bug the old tag-based registry client's
  # pruning had). No host-side (SSH) client usage remains in this class.
  #
  # Isolation contract (unchanged): this runs strictly AFTER the deploy has
  # already been marked succeeded and the app running. A failure recording
  # image_ref or issuing the prune op must NEVER flip an already-live deploy
  # back to failed/crashed — it only means rollback-to-this-deploy stays
  # unavailable, or a couple of stale build tags linger in the registry a bit
  # longer. Deploys are the source of truth for recency: the newest
  # MAX_ROLLBACK_TAGS deploys' ids are what's kept as tags in the registry,
  # whatever else is there gets pruned.
  #
  # The contract is self-enforcing: #call's entire body is wrapped in a
  # blanket `rescue StandardError`, so even a write that's part of this
  # class's own bookkeeping (`deploy.update!(image_ref:)`) or the op-issue
  # call itself can never escape and flip a succeeded deploy, or — worse, in
  # a job context — trigger ApplicationJob's `retry_on
  # ActiveRecord::Deadlocked` and re-run the whole job (including the build)
  # against an already-succeeded deploy. Losing the rollback tag/prune on
  # such a rare failure is an acceptable trade for never re-running a
  # finished deploy.
  #
  # Non-wokkud deploys (historical rows predating this rewrite) are left
  # untouched — there's no build tag to point image_ref at. The prune op is
  # still issued unconditionally: it's builder-agnostic bookkeeping on a
  # registry repo keyed by app name, not by this one deploy, and is safe
  # even for an app with zero wokkud deploys (agent 404s the repo lookup and
  # reports zeros).
  class RecordRollbackArtifact
    MAX_ROLLBACK_TAGS = 5

    def self.call(deploy:)
      new(deploy: deploy).call
    end

    def initialize(deploy:)
      @deploy = deploy
      @app = deploy.app_record
    end

    def call
      deploy.update!(image_ref: deploy.wokkud_image_ref) if deploy.builder == "wokkud"
      prune_build_tags
      deploy.image_ref
    rescue StandardError => e
      Rails.logger.warn("Deploys::RecordRollbackArtifact: unexpected error recording rollback artifact for #{app.name}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end

    private

    attr_reader :deploy, :app

    # Fire-and-forget: the agent prunes asynchronously, and a prune failure
    # (or op-issue failure — e.g. a live stack.converge already holds this
    # app's one-live-op slot) is covered by #call's blanket rescue same as
    # everything else here.
    def prune_build_tags
      keep = app.deploys.where.not(image_ref: nil).order(created_at: :desc)
                .limit(MAX_ROLLBACK_TAGS).pluck(:image_ref).map { |ref| ref.split(":").last }.uniq
      Lifecycle::Ops.issue!(app, "registry.prune", { "repo" => "wokku/#{app.name}", "keep_tags" => keep },
                            wait: false, timeout: 10)
    end
  end
end
