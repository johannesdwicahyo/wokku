module Cron
  # Persists wokkud-reported cron runs and drives the failing/recovered
  # notification state machine, derived purely from run rows (no new columns).
  class RunRecorder
    include Notifiable

    STREAK = 3

    def initialize(server)
      @server = server
    end

    # rows: array of permitted hashes from the agent. Returns count recorded.
    def call(rows)
      recorded = 0
      rows.each do |row|
        task = ScheduledTask.joins(:app_record)
                            .where(app_records: { server_id: @server.id })
                            .find_by(id: row["task_id"])
        next unless task # deleted mid-flight, or app not on this server — normal
        begin
          run = task.runs.create!(
            started_at: row["started_at"],
            finished_at: row["finished_at"],
            exit_code: row["exit_code"],
            skipped_reason: row["skipped_reason"],
            log_excerpt: row["log_excerpt"]
          )
          recorded += 1
          notify_transitions(task, run)
        rescue StandardError => e
          Rails.logger.warn("cron run ingest: #{e.class}: #{e.message}")
          next
        end
      end
      recorded
    end

    private

    def notify_transitions(task, run)
      return if run.skipped_reason.present?
      # Assumes wokkud reports arrive in order per task (near-real-time heartbeats),
      # so recent[0] == this run. Out-of-order/backfilled reports could miscompute the streak.
      recent = task.runs.where(skipped_reason: nil).order(started_at: :desc, created_at: :desc).limit(STREAK + 1).to_a
      codes = recent.map(&:exit_code)
      app = task.app_record

      if run.exit_code.to_i.positive?
        streak = codes.take_while { |c| c.to_i.positive? }.length
        if streak == STREAK
          fire_team_event(app.team, "scheduled_task_failing",
            { app_name: app.name, task_command: task.command, exit_code: run.exit_code })
        end
      elsif codes[1].to_i.positive?
        prior_streak = codes.drop(1).take_while { |c| c.to_i.positive? }.length
        fire_team_event(app.team, "scheduled_task_recovered",
          { app_name: app.name, task_command: task.command }) if prior_streak >= STREAK
      end
    end
  end
end
