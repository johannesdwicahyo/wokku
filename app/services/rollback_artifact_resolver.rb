# Shared rollback-artifact resolution (Track A Phase 4a Task 4, dashboard
# rider). Both Api::V1::ReleasesController#rollback and
# Dashboard::ReleasesController#rollback need the exact same answer to "can
# we roll back to this release, and with which artifact" — this used to
# live only in the API controller (#resolve_rollback_artifact +
# #rollback_artifact_missing_hint); extracted here so the dashboard's
# rollback button gets the real path instead of the old commit_sha/
# `ps:rebuild` placebo.
#
# Resolution order, checked against live host/store state (not just the
# column):
#
#   1. image_ref present AND still live -> fast path, `from_image`. image_ref
#      is a local-registry ref (`127.0.0.1:5000/wokku-rollback/<app>:<id>`)
#      whose durable home is `Hosts::Registry`, checked via its tags API —
#      dokku's post-deploy cleanup routinely rmis the local docker tag, so
#      `docker images` would false-negative it. Legacy local-format refs
#      (no registry prefix) were swept from prod 2026-07-28 and image_refs
#      backfilled to registry refs; a non-registry ref now simply resolves
#      as not-live and falls through to the archive path / hint.
#   2. archive_key present AND the object still exists in the archive
#      store -> slower path, `from_archive` (rebuild).
#   3. neither -> artifact_available? is false, `hint` explains why (covers
#      "artifact was pruned" and legacy releases that never recorded one).
class RollbackArtifactResolver
  Result = Struct.new(:image_ref, :archive_key, :hint, keyword_init: true) do
    def artifact_available?
      image_ref.present? || archive_key.present?
    end
  end

  def self.call(app_record:, release:, target_deploy:)
    new(app_record: app_record, release: release, target_deploy: target_deploy).call
  end

  def initialize(app_record:, release:, target_deploy:)
    @app_record = app_record
    @release = release
    @target_deploy = target_deploy
  end

  def call
    image_ref, archive_key = resolve_artifact
    hint = rollback_artifact_missing_hint if image_ref.blank? && archive_key.blank?
    Result.new(image_ref: image_ref, archive_key: archive_key, hint: hint)
  end

  private

  attr_reader :app_record, :release, :target_deploy

  # Returns [image_ref, archive_key] — exactly one populated (whichever
  # artifact is still usable), or [nil, nil] if neither is.
  def resolve_artifact
    return [ nil, nil ] unless target_deploy

    if target_deploy.image_ref.present?
      return [ target_deploy.image_ref, nil ] if rollback_image_live?(target_deploy.image_ref)
    end

    if target_deploy.archive_key.present?
      return [ nil, target_deploy.archive_key ] if Wokku.config.backup_store.exists?(target_deploy.archive_key)
    end

    [ nil, nil ]
  end

  # image_ref is a local-registry ref (127.0.0.1:5000/...) whose durable
  # home is the registry — dokku's post-deploy cleanup routinely rmis the
  # local tag, so liveness must be answered by the registry API, not
  # `docker images`. Non-registry refs (legacy local format, swept from
  # prod 2026-07-28) resolve as not-live.
  def rollback_image_live?(ref)
    prefix = "#{Hosts::Registry::HOST}/"
    return false unless ref.start_with?(prefix)

    repo, tag = ref.delete_prefix(prefix).split(":")
    Hosts::Registry.new(Hosts::Ssh.new(app_record.server)).tags(repo).include?(tag)
  end

  def rollback_artifact_missing_hint
    unless target_deploy
      return "v#{release.version} has no recorded deploy at all. Trigger a fresh deploy instead of rolling back to this release."
    end

    pruned = []
    pruned << "its rollback image tag was pruned from the host (or the registry)" if target_deploy.image_ref.present?
    pruned << "its uploaded archive is no longer in storage" if target_deploy.archive_key.present?
    reason = pruned.presence&.join(" and ") || "no build artifact (image or archive) was ever recorded for it — a legacy deploy"
    "Cannot roll back to v#{release.version}: #{reason}. Trigger a fresh deploy instead."
  end
end
