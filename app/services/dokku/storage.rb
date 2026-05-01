require "shellwords"

module Dokku
  # Wraps `dokku storage:*` for managing host-bind-mount volumes on an app.
  # Used by the StorageController + the template_deployer's storage_mounts
  # path, so stateful templates (Uptime Kuma, n8n, etc.) survive redeploys.
  class Storage
    def initialize(client)
      @client = client
    end

    # List of "host_path:container_path" mount strings. Empty when the app
    # has no mounts configured.
    def list(app_name)
      output = @client.run("storage:list #{Shellwords.escape(app_name)}").to_s.strip
      return [] if output.empty?
      output.lines.map(&:strip).reject do |l|
        l.empty? ||
          l.start_with?("=====>") ||
          l.start_with?("-----") ||
          l == "No mounts in app #{app_name}" ||
          l.match?(/\A[a-z]+ Storage Mounts:/i)
      end
    end

    # Pre-create /var/lib/dokku/data/storage/<app>/ owned by the dokku user
    # so subsequent `storage:mount` calls have a writable host dir.
    def ensure_directory(app_name)
      @client.run("storage:ensure-directory #{Shellwords.escape(app_name)}")
    end

    # mount_spec is "host_path:container_path", e.g.
    # "/var/lib/dokku/data/storage/foo/data:/app/data".
    def mount(app_name, mount_spec)
      @client.run("storage:mount #{Shellwords.escape(app_name)} #{Shellwords.escape(mount_spec)}")
    end

    def unmount(app_name, mount_spec)
      @client.run("storage:unmount #{Shellwords.escape(app_name)} #{Shellwords.escape(mount_spec)}")
    end
  end
end
