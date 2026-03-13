require "tty-table"

module Wokku
  module Commands
    class Domains
      def list(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        domains = client.get("apps/#{app_id}/domains")

        if domains.empty?
          puts "No custom domains configured."
          return
        end

        header = %w[ID Domain SSL Created]
        rows = domains.map do |d|
          ssl = d["ssl_enabled"] ? pastel.green("enabled") : pastel.yellow("disabled")
          [d["id"], d["domain"], ssl, d["created_at"]&.slice(0, 10)]
        end

        table = TTY::Table.new(header: header, rows: rows)
        puts table.render(:unicode, padding: [0, 1])
      end

      def add(app_id, domain)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/domains", { domain: domain })
        puts pastel.green("Added domain #{pastel.bold(domain)}")
      end

      def remove(app_id, domain_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.delete("apps/#{app_id}/domains/#{domain_id}")
        puts pastel.green("Removed domain #{domain_id}")
      end

      def enable_ssl(app_id, domain_id)
        pastel = Pastel.new
        client = ApiClient.new
        client.post("apps/#{app_id}/domains/#{domain_id}/ssl")
        puts pastel.green("SSL enabled for domain #{domain_id}")
      end
    end
  end
end
