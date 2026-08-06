module Preview
  class IdleSweepJob < ApplicationJob
    queue_as :default

    def perform
      Preview::IdleSweeper.sweep
    end
  end
end
