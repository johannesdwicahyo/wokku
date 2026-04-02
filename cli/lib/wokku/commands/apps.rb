require "tty-table"
require "tty-prompt"

module Wokku
  module Commands
    class Apps
      def list
        pastel = Pastel.new
        client = ApiClient.new
        apps = client.get("apps")

        if apps.empty?
          puts "No apps found. Create one with: wokku apps:create"
          return
        end

        header = %w[Name Status Server Created]
        rows = apps.map do |app|
          status = case app["status"]
          when "running" then pastel.green(app["status"])
          when "stopped" then pastel.red(app["status"])
          else pastel.yellow(app["status"] || "unknown")
          end
          [ app["name"], status, app["server_id"], app["created_at"]&.slice(0, 10) ]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [ 0, 1 ])
      end

      def create(name, server_id:, branch: "main")
        pastel = Pastel.new
        client = ApiClient.new
        data = client.post("apps", { name: name, server_id: server_id, deploy_branch: branch })
        puts pastel.green("Created app #{pastel.bold(data["name"])}")
      end

      def destroy(app_id, confirm: nil)
        pastel = Pastel.new
        client = ApiClient.new

        app = client.get("apps/#{app_id}")
        app_name = app["name"]

        unless confirm == app_name
          prompt = TTY::Prompt.new
          answer = prompt.ask("To confirm, type the app name (#{app_name}):")
          unless answer == app_name
            puts pastel.red("Confirmation failed. Aborting.")
            return
          end
        end

        client.delete("apps/#{app_id}")
        puts pastel.green("Destroyed app #{app_name}")
      end

      def info(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        app = client.get("apps/#{app_id}")

        puts pastel.bold("=== #{app["name"]}")
        puts "ID:            #{app["id"]}"
        puts "Status:        #{app["status"]}"
        puts "Server:        #{app["server_id"]}"
        puts "Deploy Branch: #{app["deploy_branch"]}"
        puts "Created:       #{app["created_at"]}"
        puts "Updated:       #{app["updated_at"]}"
      end

      def rename(app_id, new_name)
        pastel = Pastel.new
        client = ApiClient.new
        data = client.patch("apps/#{app_id}", { name: new_name })
        puts pastel.green("Renamed app to #{pastel.bold(data["name"])}")
      end
    end
  end
end
