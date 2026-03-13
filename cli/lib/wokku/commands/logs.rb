module Wokku
  module Commands
    class Logs
      def show(app_id, tail: false, lines: 100)
        pastel = Pastel.new
        client = ApiClient.new

        if tail
          loop do
            data = client.get("apps/#{app_id}/logs", { lines: lines })
            log_lines = extract_lines(data)
            log_lines.each { |line| puts line }
            sleep 2
          rescue Interrupt
            break
          end
        else
          data = client.get("apps/#{app_id}/logs", { lines: lines })
          log_lines = extract_lines(data)
          if log_lines.empty?
            puts "No logs available."
          else
            log_lines.each { |line| puts line }
          end
        end
      end

      private

      def extract_lines(data)
        if data.is_a?(Hash) && data["logs"]
          Array(data["logs"])
        elsif data.is_a?(Array)
          data
        elsif data.is_a?(String)
          data.split("\n")
        else
          []
        end
      end
    end
  end
end
