module Apps
  module Cron
    class Error < StandardError
      attr_reader :code

      def initialize(message, code: :error)
        super(message)
        @code = code
      end
    end
  end
end
