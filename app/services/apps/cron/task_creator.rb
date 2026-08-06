module Apps
  module Cron
    class TaskCreator
      def initialize(app)
        @app = app
      end

      # wokkud-cron servers pick up ScheduledTask rows directly — no dokku
      # crontab sync (W7 Phase 1 dead-branch collapse).
      def call!(command:, schedule:, description: nil)
        task = @app.scheduled_tasks.new(command: command, schedule: schedule, description: description)
        unless task.save
          raise Apps::Cron::Error.new(task.errors.full_messages.join("; "), code: :invalid)
        end

        task
      end
    end
  end
end
