module ImageScans
  # Runs after a successful scan report: narrates a deploy-triggered scan into
  # that deploy's own log (same append + broadcast as the build log lines), and
  # notifies on NEW critical vulnerabilities. Idempotent: a repeated call (late
  # report path) finds the log line present / notified_at claimed and no-ops.
  class AfterReport
    def self.call(scan)
      append_deploy_log(scan)
      notify_new_critical(scan)
    end

    def self.append_deploy_log(scan)
      return unless scan.via_deploy? && scan.deploy

      c = scan.counts || {}
      line = "Image scan: #{c["critical"].to_i} critical · #{c["high"].to_i} high (#{c["fixable"].to_i} fixable)\n"
      appended = Deploy.where(id: scan.deploy_id)
        .where("COALESCE(log, '') NOT LIKE ?", "%#{line}%")
        .update_all([ "log = COALESCE(log, '') || ?", line ])
      DeployChannel.broadcast_to(scan.deploy, { type: "log", data: line }) if appended == 1
    end

    # New = critical ids not in the app's newest earlier succeeded scan (any
    # image). Only the app's CURRENT image alerts; a superseded image never does.
    def self.notify_new_critical(scan)
      return unless Wokku.config.image_scans? && scan.succeeded? && scan.notified_at.nil?

      app = scan.app_record
      current = Release.joins(:deploy).where(app_record_id: app.id, deploys: { status: Deploy.statuses[:succeeded] })
                       .order(version: :desc).first&.deploy
      return unless current && current.image_ref == scan.image_ref

      prev = ImageScan.where(app_record_id: app.id, status: :succeeded).where("id <> ? AND created_at < ?", scan.id, scan.created_at)
                      .order(created_at: :desc).first
      new_ids = critical_ids(scan) - (prev ? critical_ids(prev) : [])
      return if new_ids.empty?
      return unless ImageScan.where(id: scan.id, notified_at: nil).update_all(notified_at: Time.current) == 1

      team = app.team
      context = { "app_id" => app.id, "app_name" => app.name, "count" => new_ids.size, "ids" => new_ids.first(3).join(", "),
                  "locale" => (team.owner&.locale.presence || I18n.default_locale).to_s }
      team.notifications.where(app_record_id: [ nil, app.id ]).find_each do |n|
        next unless n.events.include?("image_scan_critical")
        NotifyJob.perform_later(n.id, "image_scan_critical", scan.deploy_id || current.id, context)
      end
      Activity.log(user: team.owner, team: team, action: "app.image_scan.critical", target: app,
                   metadata: { count: new_ids.size, ids: new_ids.first(3), image_ref: scan.image_ref })
    rescue StandardError => e
      ImageScan.where(id: scan.id).update_all(notified_at: nil) # let a retry notify
      Rails.logger.warn("[ImageScans::AfterReport] notify #{scan.id}: #{e.class}: #{e.message}")
    end

    # ponytail: only the stored top-50 findings are visible, so >50 criticals can mis-diff; fine for an alert.
    def self.critical_ids(scan)
      (scan.findings || []).select { |f| f["severity"].to_s.casecmp?("critical") }.map { |f| f["id"] }.compact.uniq
    end
  end
end
