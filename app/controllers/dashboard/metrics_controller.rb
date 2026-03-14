module Dashboard
  class MetricsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @metrics = @app.metrics.order(recorded_at: :asc).limit(100)
      @processes = fetch_processes
      @resources = fetch_resources
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def fetch_processes
      client = Dokku::Client.new(@app.server)
      output = client.run("ps:report #{@app.name}")
      processes = []
      output.each_line do |line|
        line = line.strip
        if (match = line.match(/Status (\w+) (\d+):\s+(\w+)\s*\(CID:\s*(\w+)\)/))
          processes << {
            type: match[1],
            index: match[2].to_i,
            status: match[3],
            container_id: match[4]
          }
        end
      end
      processes
    rescue => e
      Rails.logger.warn "Failed to fetch processes for #{@app.name}: #{e.message}"
      []
    end

    def fetch_resources
      client = Dokku::Client.new(@app.server)
      output = client.run("resource:report #{@app.name}")
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        if (match = line.match(/\A\s+(.+?):\s+(.*)\z/))
          key = match[1].strip.parameterize(separator: "_")
          result[key] = match[2].strip
        end
      end
      result
    rescue => e
      Rails.logger.warn "Failed to fetch resources for #{@app.name}: #{e.message}"
      {}
    end
  end
end
