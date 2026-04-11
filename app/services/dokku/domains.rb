require "shellwords"

module Dokku
  class Domains
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("domains:report #{Shellwords.escape(app_name)}")
      vhosts = output.lines.find { |l| l.include?("Domains app vhosts:") }
      return [] unless vhosts
      vhosts.split(":").last.strip.split
    end

    def add(app_name, domain)
      @client.run("domains:add #{Shellwords.escape(app_name)} #{Shellwords.escape(domain)}")
    end

    def remove(app_name, domain)
      @client.run("domains:remove #{Shellwords.escape(app_name)} #{Shellwords.escape(domain)}")
    end

    def enable_ssl(app_name, domain = nil)
      # letsencrypt:enable applies to all domains on the app in Dokku.
      # If a specific domain is requested, ensure it exists first via `domains:add`.
      if domain
        add(app_name, domain)
      end
      @client.run("letsencrypt:enable #{Shellwords.escape(app_name)}")
    end
  end
end
