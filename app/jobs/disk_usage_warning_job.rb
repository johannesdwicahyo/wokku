# Spec 2026-09-24 §6: disk is a soft quota — warn at 90%, never block.
class DiskUsageWarningJob < ApplicationJob
  queue_as :default
  THRESHOLD = 0.9

  def perform
    AppRecord.where("volume_disk_gb > 0").includes(:server, team: :owner).find_each do |app|
      warn(app, app.team&.owner, "#{app.name} · disk", app.volume_used_gb, app.volume_disk_gb)
    end
    DatabaseService.where(shared: false).where.not(disk_gb: nil).includes(:server).find_each do |db|
      warn(db, db.billing_team&.owner, "#{db.name} · #{db.service_type}", db.disk_used_gb, db.disk_gb)
    end
  end

  private

  def warn(record, owner, label, used, allocated)
    ratio = Resources::DiskUsage.ratio(record)
    return unless owner && ratio && ratio >= THRESHOLD
    return unless Rails.cache.write("disk-warn:#{record.class.name}:#{record.id}", true, expires_in: 1.day, unless_exist: true)
    ResourceMailer.disk_almost_full(owner, label: label, used_gb: used, allocated_gb: allocated).deliver_later
  end
end
