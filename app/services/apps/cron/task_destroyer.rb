module Apps
  module Cron
    class TaskDestroyer
      def initialize(app)
        @app = app
      end

      # wokkud-cron servers pick up ScheduledTask rows directly — no dokku
      # crontab sync (W7 Phase 1 dead-branch collapse).
      def call!(task)
        task.destroy!
        true
      end
    end
  end
end
