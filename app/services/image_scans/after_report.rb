module ImageScans
  # Hook run after a successful scan report (filled in by later tasks).
  class AfterReport
    def self.call(_scan) = nil
  end
end
