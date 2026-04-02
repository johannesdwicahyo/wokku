require "tty-table"

module Wokku
  module Commands
    class Config
      def list(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        data = client.get("apps/#{app_id}/config")

        config = data.is_a?(Hash) && data["config"] ? data["config"] : data
        if config.nil? || config.empty?
          puts "No config vars set for this app."
          return
        end

        header = %w[Key Value]
        rows = config.map { |k, v| [ k, v ] }
        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [ 0, 1 ])
      end

      def set(app_id, pairs)
        pastel = Pastel.new
        client = ApiClient.new

        vars = {}
        pairs.each do |pair|
          key, value = pair.split("=", 2)
          unless key && value
            puts pastel.red("Invalid format: #{pair}. Use KEY=VALUE")
            exit 1
          end
          vars[key] = value
        end

        client.patch("apps/#{app_id}/config", { config: vars })
        puts pastel.green("Config vars set for app #{app_id}")
      end

      def unset(app_id, keys)
        pastel = Pastel.new
        client = ApiClient.new
        client.delete("apps/#{app_id}/config", { keys: keys })
        puts pastel.green("Removed config vars: #{keys.join(", ")}")
      end

      def get(app_id, key)
        client = ApiClient.new
        data = client.get("apps/#{app_id}/config")
        config = data.is_a?(Hash) && data["config"] ? data["config"] : data
        value = config.is_a?(Hash) ? config[key] : nil
        if value
          puts "#{key}=#{value}"
        else
          puts "Key '#{key}' not found"
          exit 1
        end
      end
    end
  end
end
