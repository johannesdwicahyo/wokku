require "tty-table"

module Wokku
  module Commands
    class Releases
      def list(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        releases = client.get("apps/#{app_id}/releases")

        if releases.empty?
          puts "No releases found."
          return
        end

        header = %w[ID Version Description Created]
        rows = releases.map do |r|
          [r["id"], "v#{r["version"]}", r["description"] || "-", r["created_at"]&.slice(0, 16)]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [0, 1])
      end

      def info(app_id, release_id)
        pastel = Pastel.new
        client = ApiClient.new
        r = client.get("apps/#{app_id}/releases/#{release_id}")

        puts pastel.bold("=== Release v#{r["version"]}")
        puts "ID:          #{r["id"]}"
        puts "Description: #{r["description"]}"
        puts "Commit:      #{r["commit_sha"] || "-"}"
        puts "Created:     #{r["created_at"]}"
      end

      def rollback(app_id, release_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/releases/#{release_id}/rollback")
        puts pastel.green("Rolled back to release #{release_id}")
      end
    end
  end
end
