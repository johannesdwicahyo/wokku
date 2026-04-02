require "tty-table"

module Wokku
  module Commands
    class Addons
      def list
        pastel = Pastel.new
        client = ApiClient.new
        databases = client.get("databases")

        if databases.empty?
          puts "No addons found."
          return
        end

        header = %w[ID Name Service Status]
        rows = databases.map do |db|
          status = case db["status"]
          when "running" then pastel.green(db["status"])
          when "stopped" then pastel.red(db["status"])
          else pastel.yellow(db["status"] || "unknown")
          end
          [ db["id"], db["name"], db["service_type"], status ]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [ 0, 1 ])
      end

      def create(name, service_type:, server_id:)
        pastel = Pastel.new
        client = ApiClient.new
        data = client.post("databases", {
          name: name,
          service_type: service_type,
          server_id: server_id
        })
        puts pastel.green("Created addon #{pastel.bold(data["name"])} (#{data["service_type"]})")
      end

      def attach(database_id, app_id:)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("databases/#{database_id}/link", { app_id: app_id })
        puts pastel.green("Attached addon #{database_id} to app #{app_id}")
      end

      def detach(database_id, app_id:)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("databases/#{database_id}/unlink", { app_id: app_id })
        puts pastel.green("Detached addon #{database_id} from app #{app_id}")
      end

      def destroy(database_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.delete("databases/#{database_id}")
        puts pastel.green("Destroyed addon #{database_id}")
      end

      def info(database_id)
        pastel = Pastel.new
        client = ApiClient.new
        db = client.get("databases/#{database_id}")

        puts pastel.bold("=== #{db["name"]}")
        puts "ID:      #{db["id"]}"
        puts "Service: #{db["service_type"]}"
        puts "Status:  #{db["status"]}"
        puts "Server:  #{db["server_id"]}"
        puts "Created: #{db["created_at"]}"
      end
    end
  end
end
