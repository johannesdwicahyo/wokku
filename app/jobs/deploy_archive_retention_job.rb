# Track A Phase 4a Task 5 — nightly sweep that caps how many tarball-deploy
# archives each app keeps in the platform's DeployArchiveStore bucket. Every
# tarball deploy uploads a fresh .tar.gz (see DeployUploadsController), and
# nothing else ever deletes the older ones, so left alone the bucket grows
# unbounded. This keeps only the newest KEEP archives per app and deletes the
# rest, nulling `archive_key` on the pruned Deploy rows so
# RollbackArtifactResolver reports the typed "artifact pruned" hint instead
# of a live rollback attempt 404ing against a deleted S3 object mid-flight.
#
# Host image tags (the `image_ref` rollback artifact) are pruned at tag-time
# by Deploys::RecordRollbackArtifact (Task 3/4), not here.
#
# Keying is per S3 KEY, not per Deploy row: a rollback deploy COPIES its
# target's archive_key verbatim at creation (see RollbackArtifactResolver /
# ReleasesController#rollback), so one object in the bucket can be
# referenced by several Deploy rows across their own lifetimes. Pruning by
# row offset alone would delete an object a kept (or still in-flight) row
# still points at. Instead, per app: keep_keys is the union of (a) the
# newest KEEP terminal deploys' keys and (b) every non-terminal deploy's key
# (a pending/building row's key is always still needed — see below);
# prunable is every OTHER terminal row's key, minus keep_keys. Each
# surviving prunable key is deleted from the bucket exactly once, and
# archive_key is nulled on every Deploy row — terminal or not — that
# referenced it: structurally only terminal rows can ever reference a
# pruned key (a non-terminal row's key is always in keep_keys), but we match
# defensively across the whole row set rather than assume that invariant
# holds forever.
#
# Deliberately excludes pending/building deploys from the prunable set: a
# deploy's archive_key is written at creation time, before the build even
# starts (see DeploysController#create), so an in-flight deploy already has
# one recorded. Only terminal deploys (succeeded/failed/timed_out) are ever
# candidates for pruning.
#
# Also sweeps orphaned archives: deleting an AppRecord doesn't touch its
# `deploy-archives/<app_id>/` prefix in the bucket, so a deleted app's
# archives would otherwise live forever. We list the bucket's keys *before*
# snapshotting the live AppRecord id set (not after) so a brand-new app
# created mid-sweep can never have its just-uploaded archive misclassified
# as orphaned: its key wouldn't exist yet at list time, or if it does, its
# id will already be in the snapshot taken after.
class DeployArchiveRetentionJob < ApplicationJob
  queue_as :default

  KEEP = 5
  TERMINAL_STATUSES = %i[succeeded failed timed_out].freeze
  ARCHIVE_PREFIX = "deploy-archives/"

  def perform
    store = Wokku.config.backup_store
    return unless store.configured?

    prune_orphaned_archives(store)

    AppRecord.find_each do |app|
      prune_app(app, store)
    rescue => e
      Rails.logger.error("DeployArchiveRetentionJob: app #{app.id} failed: #{e.message}")
    end
  end

  private

  def prune_orphaned_archives(store)
    keys = store.list_keys(ARCHIVE_PREFIX)
    return if keys.empty?

    live_app_ids = AppRecord.pluck(:id).map(&:to_s).to_set

    orphaned_keys = keys.select do |key|
      app_id = key.delete_prefix(ARCHIVE_PREFIX).split("/", 2).first
      app_id.present? && !live_app_ids.include?(app_id)
    end
    return if orphaned_keys.empty?

    pruned = 0
    orphaned_keys.each do |key|
      store.delete(key)
      pruned += 1
    rescue => e
      Rails.logger.error("DeployArchiveRetentionJob: failed to delete orphaned archive #{key}: #{e.message}")
    end

    Rails.logger.info("DeployArchiveRetentionJob: pruned #{pruned}/#{orphaned_keys.size} orphaned archive(s)")
  end

  def prune_app(app, store)
    deploys = app.deploys.where.not(archive_key: nil).order(created_at: :desc).to_a
    terminal, non_terminal = deploys.partition { |d| TERMINAL_STATUSES.include?(d.status.to_sym) }

    keep_keys = terminal.first(KEEP).map(&:archive_key).to_set
    keep_keys.merge(non_terminal.map(&:archive_key))

    prunable_keys = terminal.drop(KEEP).map(&:archive_key).to_set - keep_keys
    prunable_keys.each { |key| prune_key(key, deploys, store) }
  end

  def prune_key(key, deploys, store)
    store.delete(key)
    deploys.select { |d| d.archive_key == key }.each { |d| d.update!(archive_key: nil) }
    Rails.logger.info("DeployArchiveRetentionJob: pruned archive #{key}")
  rescue => e
    Rails.logger.error("DeployArchiveRetentionJob: failed to prune archive #{key}: #{e.message}")
  end
end
