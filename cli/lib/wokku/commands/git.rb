module Wokku
  module Commands
    class Git
      def add_remote(app_id)
        pastel = Pastel.new
        client = ApiClient.new
        app = client.get("apps/#{app_id}")

        app_name = app["name"]
        server = client.get("servers/#{app["server_id"]}")
        host = server["host"]
        ssh_port = server["ssh_port"] || 22

        remote_url = "ssh://dokku@#{host}:#{ssh_port}/#{app_name}"

        # Check if remote already exists
        existing = `git remote get-url wokku 2>/dev/null`.strip
        if existing.empty?
          system("git", "remote", "add", "wokku", remote_url)
          puts pastel.green("Git remote 'wokku' added: #{remote_url}")
        else
          system("git", "remote", "set-url", "wokku", remote_url)
          puts pastel.green("Git remote 'wokku' updated: #{remote_url}")
        end

        puts "Deploy with: git push wokku main"
      end
    end
  end
end
