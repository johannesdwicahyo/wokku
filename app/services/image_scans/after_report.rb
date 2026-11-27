module ImageScans
  # Runs after a successful scan report: narrates a deploy-triggered scan into
  # that deploy's own log (same append + broadcast as the build log lines).
  # Idempotent: a repeated call finds the line already in the log and no-ops.
  class AfterReport
    def self.call(scan)
      return unless scan.via_deploy? && scan.deploy

      c = scan.counts || {}
      line = "Image scan: #{c["critical"].to_i} critical · #{c["high"].to_i} high (#{c["fixable"].to_i} fixable)\n"
      appended = Deploy.where(id: scan.deploy_id)
        .where("COALESCE(log, '') NOT LIKE ?", "%#{line}%")
        .update_all([ "log = COALESCE(log, '') || ?", line ])
      DeployChannel.broadcast_to(scan.deploy, { type: "log", data: line }) if appended == 1
    end
  end
end
