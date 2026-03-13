module Dokku
  class Domains
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("domains:report #{app_name}")
      vhosts = output.lines.find { |l| l.include?("Domains app vhosts:") }
      return [] unless vhosts
      vhosts.split(":").last.strip.split
    end

    def add(app_name, domain)
      @client.run("domains:add #{app_name} #{domain}")
    end

    def remove(app_name, domain)
      @client.run("domains:remove #{app_name} #{domain}")
    end

    def enable_ssl(app_name)
      @client.run("letsencrypt:enable #{app_name}")
    end
  end
end
