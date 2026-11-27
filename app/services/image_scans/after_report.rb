module ImageScans
  # Runs after a successful scan report: narrates a deploy-triggered scan into
  # that deploy's own log (same append + broadcast as the build log lines).
  class AfterReport
    def self.call(scan)
      return unless scan.via_deploy? && scan.deploy

      c = scan.counts || {}
      line = "Image scan: #{c["critical"].to_i} critical · #{c["high"].to_i} high (#{c["fixable"].to_i} fixable)\n"
      Deploy.where(id: scan.deploy_id).update_all([ "log = COALESCE(log, '') || ?", line ])
      DeployChannel.broadcast_to(scan.deploy, { type: "log", data: line })
    end
  end
end
