require "shellwords"
require "json"

module Dokku
  # Syncs an AppRecord's enabled ScheduledTask rows into its on-host
  # app.json `cron` array, then triggers `ps:rebuild` so Dokku's cron
  # plugin re-registers the entries.
  #
  # Survives `git push`: PostDeploySetupJob calls #sync! after every
  # successful deploy. The on-host app.json is overwritten by the
  # user's push, but we re-apply the DB-stored cron entries
  # immediately after. The DB is the source of truth; the on-host
  # app.json is a transient artifact. (Phase 3 backlog #18.)
  #
  # See: https://dokku.com/docs/processes/cron/
  class ScheduledTasks
    APP_JSON_PATH = ->(app_name) { "/home/dokku/#{app_name}/app.json" }
    REBUILD_TIMEOUT = 180 # ps:rebuild redeploys; can take a minute on cold caches

    Result = Struct.new(:success, :task_count, :error, keyword_init: true) do
      def success? = success
    end

    def initialize(app, client: nil)
      @app    = app
      @client = client || Dokku::Client.new(app.server)
    end

    # Returns a Result struct. Idempotent: safe to call repeatedly.
    def sync!
      tasks = @app.scheduled_tasks.for_sync.map(&:to_dokku_cron)
      doc = read_app_json
      doc["cron"] = tasks
      write_app_json(doc)
      rebuild! if tasks.any?
      Result.new(success: true, task_count: tasks.length)
    rescue Dokku::Client::CommandError, JSON::ParserError, StandardError => e
      Rails.logger.warn("[Dokku::ScheduledTasks] sync failed for app=#{@app.name}: #{e.class} #{e.message}")
      Result.new(success: false, task_count: 0, error: e.message)
    end

    private

    # Reads the on-host app.json. Returns {} if the file doesn't exist
    # (fresh app, no app.json yet) — Dokku tolerates this.
    def read_app_json
      raw = @client.run("cat #{Shellwords.escape(APP_JSON_PATH.call(@app.name))} 2>/dev/null || echo '{}'", timeout: 15)
      JSON.parse(raw.to_s.strip.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def write_app_json(doc)
      content = JSON.pretty_generate(doc)
      # Pipe content via stdin to a host-side `cat > path`. Avoids
      # quoting hell from embedding the JSON in the command string.
      @client.run(
        "cat > #{Shellwords.escape(APP_JSON_PATH.call(@app.name))}",
        stdin: content,
        timeout: 15
      )
    end

    def rebuild!
      @client.run("ps:rebuild #{Shellwords.escape(@app.name)}", timeout: REBUILD_TIMEOUT)
    end
  end
end
