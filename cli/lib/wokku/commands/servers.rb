require "tty-table"

module Wokku
  module Commands
    class Servers
      def list
        pastel = Pastel.new
        client = ApiClient.new
        servers = client.get("servers")

        if servers.empty?
          puts "No servers found. Add one with: wokku servers:add"
          return
        end

        header = %w[ID Name Host Status]
        rows = servers.map do |s|
          status = case s["status"]
                   when "active", "online" then pastel.green(s["status"])
                   when "offline" then pastel.red(s["status"])
                   else pastel.yellow(s["status"] || "unknown")
                   end
          [s["id"], s["name"], s["host"], status]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [0, 1])
      end

      def add(name, host:, ssh_port: 22, team_id: nil)
        pastel = Pastel.new
        client = ApiClient.new
        body = { name: name, host: host, ssh_port: ssh_port }
        body[:team_id] = team_id if team_id
        data = client.post("servers", body)
        puts pastel.green("Added server #{pastel.bold(data["name"])} (#{data["host"]})")
      end

      def remove(server_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.delete("servers/#{server_id}")
        puts pastel.green("Removed server #{server_id}")
      end

      def info(server_id)
        pastel = Pastel.new
        client = ApiClient.new
        s = client.get("servers/#{server_id}")

        puts pastel.bold("=== #{s["name"]}")
        puts "ID:       #{s["id"]}"
        puts "Host:     #{s["host"]}"
        puts "SSH Port: #{s["ssh_port"]}"
        puts "Status:   #{s["status"]}"
        puts "Created:  #{s["created_at"]}"
      end
    end
  end
end
