module Preview
  class Destroyer
    def initialize(preview_app)
      @preview = preview_app
    end

    def call
      return unless @preview && AppRecord.exists?(@preview.id)

      Preview::DnsRegistrar.new(@preview).unregister

      begin
        Lifecycle::Ops.remove_if_flagged!(@preview)
      rescue StandardError => e
        # remove_if_flagged! already swallows its own known op failures
        # (Failed/Timeout/RecordNotUnique) — this is belt-and-suspenders for
        # anything else it might raise. Teardown of the Swarm stack is
        # best-effort; the AppRecord must still go so the sweep/user-initiated
        # destroy doesn't get stuck on an orphaned stack.
        Rails.logger.warn("Preview::Destroyer teardown failed for #{@preview.name}: #{e.class}: #{e.message}")
      end

      @preview.destroy!
    end
  end
end
