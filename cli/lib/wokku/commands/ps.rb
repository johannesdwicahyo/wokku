require "tty-table"

module Wokku
  module Commands
    class Ps
      def list(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        data = client.get("apps/#{app_id}/ps")

        processes = data.is_a?(Hash) && data["processes"] ? data["processes"] : data
        if processes.nil? || (processes.is_a?(Array) && processes.empty?) || (processes.is_a?(Hash) && processes.empty?)
          puts "No processes running."
          return
        end

        if processes.is_a?(Hash)
          header = %w[Type Qty]
          rows = processes.map { |type, count| [ type, count ] }
          table = TTY::Table.new(header: header, rows: rows)
          puts table.render(:unicode, padding: [ 0, 1 ])
        else
          processes.each do |proc|
            puts "#{pastel.bold(proc["type"])}.#{proc["num"] || 1}: #{proc["state"] || "unknown"}"
          end
        end
      end

      def scale(app_id, pairs)
        pastel = Pastel.new
        client = ApiClient.new

        scaling = {}
        pairs.each do |pair|
          type, count = pair.split("=", 2)
          unless type && count
            puts pastel.red("Invalid format: #{pair}. Use TYPE=COUNT (e.g., web=2)")
            exit 1
          end
          scaling[type] = count.to_i
        end

        client.patch("apps/#{app_id}/ps", { scale: scaling })
        puts pastel.green("Scaled processes for app #{app_id}")
      end

      def restart(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/restart")
        puts pastel.green("Restarted app #{app_id}")
      end

      def stop(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/stop")
        puts pastel.green("Stopped app #{app_id}")
      end

      def start(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/start")
        puts pastel.green("Started app #{app_id}")
      end
    end
  end
end
