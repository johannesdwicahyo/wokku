require "shellwords"

# Backs up one persistent volume (a bind-mounted host dir under STORAGE_ROOT)
# for an app: tar -czf streamed from the host as root -> BackupCipher
# (AES-256-GCM) -> R2. Crash-consistent by design (live files; a mid-write
# upload is at worst torn) — anything needing transactional consistency
# belongs in a database.
#
# SECURITY: @mount reaches a ROOT shell. Every path is anchored under
# STORAGE_ROOT with no traversal/control chars (safe_mount?) at BOTH the
# inspect-parse boundary and again in #perform! (defense in depth), and every
# interpolated value is Shellwords.escape'd before it touches the command.
class VolumeBackupService
  class UnsafeMountPath < StandardError; end

  STORAGE_ROOT = "/var/lib/dokku/data/storage/".freeze
  # wokkud Swarm services mount named volumes wokku-<app>-<slug>
  # (AppRecord#mounts_for_converge); docker inspect reports their host path.
  SWARM_VOLUME = %r{\A/var/lib/docker/volumes/wokku-[A-Za-z0-9-]+/_data\z}

  # Go template printing one "host:container" line per mount of a container —
  # same spec shape the old dokku storage:list emitted.
  MOUNTS_FORMAT = '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}'.freeze

  # ponytail: 1h ceiling so a wedged tar can't pin a Puma thread forever —
  # passed straight through to run_raw_streaming's timeout: kwarg. Upgrade
  # path: move the whole tar+upload to a wokkud volume.export typed op /
  # background job at B4 cutover.
  TAR_TIMEOUT = 3600

  # A mount host path is safe to hand to a root shell only if it lives under
  # the storage root (or is a wokku Swarm named volume), has no `..` traversal, and carries no newline/NUL
  # (Shellwords escapes those, but the anchor must never be bypassable by a
  # crafted mount line).
  def self.safe_mount?(path)
    path.is_a?(String) &&
      (path.start_with?(STORAGE_ROOT) || path.match?(SWARM_VOLUME)) &&
      !path.include?("..") &&
      !path.match?(/[\n\r\0]/)
  end

  # Host paths of the app's mounts, discovered via docker inspect of the live
  # web task (apps run on Swarm; the `wokku-<app>-web.N.<taskid>` naming
  # mirrors TerminalSession#resolve_swarm_container!) and filtered to the
  # storage root. The anchor filter is also what drops non-storage Binds
  # (registry certs etc.). A mount outside the root is misconfiguration (or
  # an attack) — it is never tarred as root; log and skip. No running web
  # task -> nothing to inspect -> no mounts this cycle (warn, return []).
  def self.mount_host_paths(app_record)
    ssh = Hosts::Ssh.new(app_record.server)
    names = ssh.run_raw("docker ps --format '{{.Names}}'", timeout: 30).split("\n")
    container = names.find { |n| n.match?(/\Awokku-#{Regexp.escape(app_record.name)}-web\.\d+\./) }
    unless container
      Rails.logger.warn("[VolumeBackupService] #{app_record.name}: no running web task — skipping mount discovery")
      return []
    end

    out = ssh.run_raw("docker inspect -f #{Shellwords.escape(MOUNTS_FORMAT)} #{Shellwords.escape(container)}", timeout: 30)
    out.split("\n").filter_map do |spec|
      host = spec.to_s.split(":", 2).first.to_s.strip
      next if host.empty?
      if safe_mount?(host)
        host
      else
        Rails.logger.warn("[VolumeBackupService] #{app_record.name}: skipping non-anchored mount #{host.inspect}")
        nil
      end
    end
  end

  def initialize(app_record, mount_host_path)
    @app = app_record
    @mount = mount_host_path
    @server = app_record.server
  end

  def perform!
    raise UnsafeMountPath, "mount #{@mount.inspect} is outside #{STORAGE_ROOT}" unless self.class.safe_mount?(@mount)

    destination = @server.backup_destination
    raise "No backup destination configured for #{@server.name}" unless destination

    backup = Backup.create!(
      kind: :volume,
      app_record: @app,
      mount_path: @mount,
      backup_destination: destination,
      status: "running",
      started_at: Time.current,
      s3_key: generate_s3_key(destination.path_prefix)
    )

    enc_path = nil
    tar_tempfile = Tempfile.new([ "volume", ".tar.gz" ], binmode: true)
    begin
      ssh = Hosts::Ssh.new(@server)
      ssh.run_raw_streaming(tar_command, include_stderr: false, timeout: TAR_TIMEOUT) do |data|
        tar_tempfile.write(data)
      end
      tar_tempfile.flush

      enc_path = BackupCipher.encrypt_file(tar_tempfile.path)

      File.open(enc_path, "rb") do |f|
        destination.s3_client.put_object(
          bucket: destination.bucket,
          key: backup.s3_key,
          body: f,
          content_type: "application/octet-stream"
        )
      end

      backup.update!(
        status: "completed",
        encrypted: true,
        size_bytes: File.size(enc_path),
        completed_at: Time.current
      )

      backup
    rescue => e
      backup.update!(status: "failed", error_message: e.message, completed_at: Time.current)
      raise
    ensure
      tar_tempfile.close!
      File.unlink(enc_path) if enc_path && File.exist?(enc_path)
    end
  end

  private

  # Volumes are root-owned; a non-root host user tars through the helper
  # (which re-checks the storage root on its side too).
  def tar_command
    mount = Shellwords.escape(@mount)
    Hosts::Ssh.root_user? ? "tar -czf - -C #{mount} ." : "sudo -n /usr/local/sbin/wokku-volume-tar #{mount}"
  end

  # File.basename alone collides when an app mounts two dirs sharing a leaf
  # name (uploads/a/data + uploads/b/data). Always suffix a short digest of
  # the full host path so s3 keys stay unique and deterministic.
  def mount_slug
    "#{File.basename(@mount)}-#{Digest::SHA1.hexdigest(@mount)[0, 8]}"
  end

  def generate_s3_key(prefix)
    timestamp = Time.current.strftime("%Y-%m-%d_%H%M%S")
    # Always encrypted (AES blob, not raw gzip) — .enc suffix says so.
    # Restores key off Backup#encrypted, never the suffix.
    "#{prefix}/volume/#{@app.name}/#{mount_slug}/#{timestamp}.tar.gz.enc"
  end
end
