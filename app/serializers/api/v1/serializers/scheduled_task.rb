module Api
  module V1
    module Serializers
      class ScheduledTask
        def initialize(task)
          @task = task
        end

        def call
          {
            id: @task.id,
            command: @task.command,
            schedule: @task.schedule,
            description: @task.description,
            enabled: @task.enabled,
            created_at: @task.created_at
          }
        end
      end
    end
  end
end
