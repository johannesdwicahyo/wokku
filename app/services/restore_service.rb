class RestoreService
  IMPORT_COMMANDS = {
    "postgres" => "postgres:import",
    "mysql" => "mysql:import",
    "mariadb" => "mariadb:import",
    "mongodb" => "mongo:import",
    "redis" => "redis:import"
  }.freeze

  def initialize(backup)
    @backup = backup
    @db = backup.database_service
    @server = @db.server
    @destination = backup.backup_destination
  end

  def perform!
    cmd = IMPORT_COMMANDS[@db.service_type]
    raise "Unsupported database type for restore: #{@db.service_type}" unless cmd

    gz_tempfile = Tempfile.new(["restore", ".gz"], binmode: true)
    @destination.s3_client.get_object(
      bucket: @destination.bucket,
      key: @backup.s3_key,
      response_target: gz_tempfile.path
    )

    ssh_options = {
      port: @server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    ssh_options[:key_data] = [@server.ssh_private_key] if @server.ssh_private_key.present?

    ssh_user = @server.ssh_user || "dokku"
    import_cmd = ssh_user == "dokku" ? "#{cmd} #{@db.name}" : "dokku #{cmd} #{@db.name}"

    Net::SSH.start(@server.host, ssh_user, ssh_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(import_cmd) do |_ch, success|
          raise "Failed to execute import command" unless success

          Zlib::GzipReader.open(gz_tempfile.path) do |gz|
            while (chunk = gz.read(64 * 1024))
              ch.send_data(chunk)
            end
          end
          ch.eof!

          ch.on_extended_data { |_, _, data| Rails.logger.warn("Restore stderr: #{data}") }
        end
      end
      channel.wait
    end

    true
  rescue => e
    Rails.logger.error("RestoreService: Failed to restore #{@db.name}: #{e.message}")
    raise
  ensure
    gz_tempfile&.close
    gz_tempfile&.unlink
  end
end
