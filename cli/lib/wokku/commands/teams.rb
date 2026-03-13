require "tty-table"

module Wokku
  module Commands
    class Teams
      def create(name)
        pastel = Pastel.new
        client = ApiClient.new
        data = client.post("teams", { name: name })
        puts pastel.green("Created team #{pastel.bold(data["name"])}")
      end

      def members(team_id)
        pastel = Pastel.new
        client = ApiClient.new
        members = client.get("teams/#{team_id}/members")

        if members.empty?
          puts "No members found."
          return
        end

        header = %w[ID Email Role]
        rows = members.map do |m|
          user = m["user"] || m
          [user["id"] || m["id"], user["email"] || m["email"], m["role"] || "-"]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [0, 1])
      end

      def invite(team_id, email:, role: "member")
        pastel = Pastel.new
        client = ApiClient.new
        client.post("teams/#{team_id}/members", { email: email, role: role })
        puts pastel.green("Invited #{pastel.bold(email)} to team as #{role}")
      end
    end
  end
end
