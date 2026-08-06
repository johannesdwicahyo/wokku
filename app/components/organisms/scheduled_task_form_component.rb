module Organisms
  # Form for creating a ScheduledTask. Used by
  # Dashboard::ScheduledTasksController#new. Brutalist single-card form
  # with three fields (command, schedule, description) + an enabled
  # checkbox + a submit button.
  class ScheduledTaskFormComponent < ApplicationComponent
    def initialize(task:, app:)
      @task = task
      @app  = app
    end
    attr_reader :task, :app
  end
end
