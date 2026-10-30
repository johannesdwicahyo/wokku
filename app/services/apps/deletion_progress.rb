module Apps
  # Live progress of an app deletion (AppDestroyJob → Apps::Destroyer).
  # State lives in the shared cache so a reload mid-delete shows where it
  # is; every change is pushed to the dashboard over Turbo Streams.
  class DeletionProgress
    TTL = 1.hour

    def self.stream(app_id) = "app_deletion_#{app_id}"
    def self.key(app_id) = "app_deletion:#{app_id}"

    # Read for a viewer; nil unless it belongs to one of their teams.
    def self.for(app_id, user)
      data = Rails.cache.read(key(app_id))
      data if data && user.teams.exists?(id: data[:team_id])
    end

    def self.start!(app)
      new(app.id, { app_name: app.name, team_id: app.team_id, state: "running",
                    steps: [ { label: "Queued", state: "done" } ] }).tap(&:save_and_broadcast)
    end

    def self.load(app_id)
      data = Rails.cache.read(key(app_id))
      data && new(app_id, data)
    end

    attr_reader :data

    def initialize(app_id, data)
      @app_id = app_id
      @data = data
    end

    def step(label, state)
      existing = @data[:steps].find { |s| s[:label] == label }
      existing ? existing[:state] = state.to_s : @data[:steps] << { label: label, state: state.to_s }
      save_and_broadcast
    end

    def finish!(state)
      @data[:state] = state.to_s
      save_and_broadcast
    end

    def save_and_broadcast
      Rails.cache.write(self.class.key(@app_id), @data, expires_in: TTL)
      Turbo::StreamsChannel.broadcast_replace_to(
        self.class.stream(@app_id),
        target: "app_deletion_#{@app_id}",
        html: ApplicationController.render(Organisms::AppDeletionProgressComponent.new(app_id: @app_id, progress: @data), layout: false)
      )
    rescue StandardError => e
      # Progress is cosmetic; it must never break the deletion itself.
      Rails.logger.warn("Apps::DeletionProgress: #{e.class}: #{e.message}")
    end
  end
end
