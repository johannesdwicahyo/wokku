require "zlib"

# Imports a user-supplied dump (plain SQL or pg_dump -Fc for postgres,
# mysqldump for mysql/mariadb, mongodump --archive for mongodb) into a
# wokkud-managed database: gzip it to a temporary object in the server's
# backup bucket and run the same service.import op backup restores use.
# The agent pulls it over a presigned URL; the object is deleted afterwards.
class ImportService
  include DatabaseImportTarget

  SUPPORTED_TYPES = %w[postgres mysql mariadb mongodb].freeze

  class UnsupportedTypeError < StandardError; end

  def initialize(database_service:, dump_io:)
    @db = database_service
    @dump_io = dump_io
    @server = database_service.server
  end

  def perform!
    unless SUPPORTED_TYPES.include?(@db.service_type)
      raise UnsupportedTypeError, "Import isn't supported for #{@db.service_type}" \
        "#{" (restore an RDB file manually)" if @db.service_type == "redis"}"
    end
    raise UnsupportedTypeError, "Import needs a wokkud-managed database" unless @db.wokkud_managed?

    destination = @server.backup_destination
    raise "No backup destination configured for #{@server.name}" unless destination

    key = "imports/#{@db.id}/#{SecureRandom.hex(8)}.gz"
    gz = Tempfile.new([ "import", ".gz" ], binmode: true)
    begin
      Zlib::GzipWriter.wrap(gz) do |w|
        while (chunk = @dump_io.read(64 * 1024))
          w.write(chunk)
        end
        w.finish
      end
      gz.flush
      File.open(gz.path, "rb") { |f| destination.s3_client.put_object(bucket: destination.bucket, key: key, body: f) }
      Services::Ops.issue_and_wait!(
        service: managed_op_service,
        kind: "service.import",
        params: {
          service_type: @db.service_type,
          database: managed_op_database,
          password: dsn_password,
          presigned_get_url: destination.s3_presigned_url(key)
        }.compact
      )
      true
    ensure
      gz.close!
      begin
        destination.s3_client.delete_object(bucket: destination.bucket, key: key)
      rescue StandardError => e
        Rails.logger.warn("ImportService: temp object #{key} not deleted: #{e.message}")
      end
    end
  end
end
