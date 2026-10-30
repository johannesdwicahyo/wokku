class RestoreService
  include DatabaseImportTarget

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

    return perform_managed! if @db.wokkud_managed?

    gz_tempfile = Tempfile.new([ "restore", ".gz" ], binmode: true)
    @destination.s3_client.get_object(
      bucket: @destination.bucket,
      key: @backup.s3_key,
      response_target: gz_tempfile.path
    )

    gz_path = @backup.encrypted? ? BackupCipher.decrypt_file(gz_tempfile.path) : gz_tempfile.path

    ssh_options = {
      port: @server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    ssh_options[:key_data] = [ @server.ssh_private_key ] if @server.ssh_private_key.present?

    ssh_user = @server.ssh_user || "dokku"
    import_cmd = ssh_user == "dokku" ? "#{cmd} #{@db.name}" : "dokku #{cmd} #{@db.name}"

    Net::SSH.start(@server.host, ssh_user, ssh_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(import_cmd) do |_ch, success|
          raise "Failed to execute import command" unless success

          Zlib::GzipReader.open(gz_path) do |gz|
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
    # Decrypted temp holds a plaintext DB dump — remove it on every path.
    if gz_path && gz_path != gz_tempfile&.path && File.exist?(gz_path)
      File.unlink(gz_path)
    end
  end

  private

  # Phase B4: wokkud-managed services download the presigned GET straight
  # into the engine's restore command over docker exec — replaces the
  # Net::SSH + Tempfile pipe above. Errors propagate to #perform!'s rescue.
  def perform_managed!
    get_url = @destination.s3_presigned_url(@backup.s3_key)
    Services::Ops.issue_and_wait!(
      service: managed_op_service,
      kind: "service.import",
      params: managed_op_params(get_url)
    )
    true
  end

  def managed_op_params(url)
    {
      service_type: @db.service_type,
      database: managed_op_database,
      password: dsn_password,
      presigned_get_url: url,
      dek: managed_dek,
      replace: true # wokkud empties the target in the same transaction
    }.compact
  end

  # WKB1 restores: fetch just the envelope header (ranged GET — no full
  # download), unwrap this backup's DEK with the control-plane private key,
  # and hand it to the agent. The agent alone can never decrypt (B4 trust
  # model); pre-sweep plaintext backups return nil (compact drops the key).
  def managed_dek
    return nil unless @backup.encrypted?

    header = @destination.s3_client.get_object(
      bucket: @destination.bucket, key: @backup.s3_key, range: "bytes=0-1023"
    ).body.read
    Base64.strict_encode64(
      EnvelopeCipher.unwrap_dek(header, private_key: EnvelopeCipher.master_private_key)
    )
  end

end
