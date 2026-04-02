class BackupService
  EXPORT_COMMANDS = {
    "postgres" => "postgres:export",
    "mysql" => "mysql:export",
    "mariadb" => "mariadb:export",
    "mongodb" => "mongo:export",
    "redis" => "redis:export"
  }.freeze

  def initialize(database_service)
    @db = database_service
    @server = database_service.server
  end

  def perform!
    destination = @server.backup_destination
    raise "No backup destination configured for #{@server.name}" unless destination

    backup = @db.backups.create!(
      backup_destination: destination,
      status: "running",
      started_at: Time.current,
      s3_key: generate_s3_key(destination.path_prefix)
    )

    begin
      client = Dokku::Client.new(@server)
      raw_tempfile = Tempfile.new([ "backup_raw", ".dump" ], binmode: true)
      gz_tempfile = Tempfile.new([ "backup", ".gz" ], binmode: true)

      client.run_streaming(export_command) do |data|
        raw_tempfile.write(data)
      end
      raw_tempfile.rewind

      Zlib::GzipWriter.open(gz_tempfile.path) do |gz|
        while (chunk = raw_tempfile.read(64 * 1024))
          gz.write(chunk)
        end
      end

      destination.s3_client.put_object(
        bucket: destination.bucket,
        key: backup.s3_key,
        body: File.open(gz_tempfile.path, "rb"),
        content_type: "application/gzip"
      )

      backup.update!(
        status: "completed",
        size_bytes: File.size(gz_tempfile.path),
        completed_at: Time.current
      )

      backup
    rescue => e
      backup.update!(
        status: "failed",
        error_message: e.message,
        completed_at: Time.current
      )
      raise
    ensure
      raw_tempfile&.close; raw_tempfile&.unlink
      gz_tempfile&.close; gz_tempfile&.unlink
    end
  end

  private

  def export_command
    cmd = EXPORT_COMMANDS[@db.service_type]
    raise "Unsupported database type for backup: #{@db.service_type}" unless cmd
    "#{cmd} #{@db.name}"
  end

  def generate_s3_key(prefix)
    timestamp = Time.current.strftime("%Y-%m-%d_%H%M%S")
    "#{prefix}/#{@db.service_type}/#{@db.name}/#{timestamp}.gz"
  end
end
