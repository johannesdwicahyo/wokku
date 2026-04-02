require "tty-table"

module Wokku
  module Commands
    class Notifications
      def list
        pastel = Pastel.new
        client = ApiClient.new
        notifications = client.get("notifications")

        if notifications.empty?
          puts "No notification channels configured."
          return
        end

        header = %w[ID Channel Target]
        rows = notifications.map do |n|
          [ n["id"], n["channel"], n["target"] || n["url"] || "-" ]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [ 0, 1 ])
      end

      def add(channel, target:)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("notifications", { channel: channel, target: target })
        puts pastel.green("Added #{channel} notification")
      end
    end
  end
end
