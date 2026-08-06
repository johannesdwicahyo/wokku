module Services
  # Issues datastore ops for wokkud and (optionally) waits for the agent
  # to report. The synchronous waiter exists because today's callers
  # (provisioner jobs) are themselves synchronous — they swap an SSH call
  # for an op without changing their own shape.
  class Ops
    class Failed < StandardError
      attr_reader :op
      def initialize(op)
        @op = op
        super("#{op.kind} failed: #{op.error} (#{op.error_code})")
      end
    end
    class Timeout < StandardError; end

    POLL_INTERVAL = 2

    def self.issue!(service:, kind:, params: {})
      ServiceOp.create!(database_service: service, server: service.server, kind: kind, params: params)
    end

    def self.issue_and_wait!(service:, kind:, params: {}, timeout: 300)
      op = issue!(service: service, kind: kind, params: params)
      deadline = Time.current + timeout
      loop do
        op.reload
        return op if op.succeeded?
        raise Failed, op if op.failed?
        raise Timeout, "#{kind} on #{service.name} not finished after #{timeout}s" if Time.current > deadline
        sleep POLL_INTERVAL
      end
    end
  end
end
