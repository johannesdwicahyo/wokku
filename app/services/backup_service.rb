class BackupService
  # memcached intentionally omitted (no export path, genuinely ephemeral) —
  # see ServiceTier::BACKUP_POLICIES and BackupSchedulerJob::BACKUPABLE_TYPES.
  # redis:export streams the RDB snapshot (binary; gzip+encrypt pipeline
  # handles it the same as SQL dumps).
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

    perform_managed!(destination, backup)
  end

  private

  # Phase B4: wokkud-managed services stream a service.export op straight
  # to R2 via a presigned PUT (no Rails-side SSH/tempfile buffering).
  # The agent WKB1-encrypts before the PUT (per-backup DEK wrapped to the
  # control-plane public key sent below) — see EnvelopeCipher.
  def perform_managed!(destination, backup)
    export_command # raises for unsupported types
    put_url = destination.s3_presigned_put(backup.s3_key)
    op = Services::Ops.issue_and_wait!(
      service: managed_op_service,
      kind: "service.export",
      params: managed_op_params(put_url)
    )
    backup.update!(status: "completed", encrypted: true, size_bytes: op.result["bytes"], completed_at: Time.current)
    backup
  rescue => e
    backup.update!(status: "failed", error_message: e.message, completed_at: Time.current)
    raise
  end

  # Shared tenants live inside the parent's container — the op targets
  # the parent (its container), scoped to this tenant's db via `database:`.
  # Dedicated services own their container outright.
  def managed_op_service
    @db.shared? ? @db.parent_service : @db
  end

  def managed_op_database
    @db.shared? ? @db.shared_db_name : @db.dedicated_db_name
  end

  def managed_op_params(url)
    {
      service_type: @db.service_type,
      database: managed_op_database,
      password: dsn_password,
      presigned_put_url: url,
      public_key_pem: EnvelopeCipher.public_key_pem
    }.compact
  end

  # A shared tenant's DSN holds the TENANT's password, not the parent's
  # root one — send none: postgres dumps as the local superuser, mariadb
  # reads the root password from the parent container's env (wokkud).
  def dsn_password
    return nil if @db.shared?
    @db.dsn.present? ? URI.parse(@db.dsn).password : nil
  end

  def export_command
    cmd = EXPORT_COMMANDS[@db.service_type]
    raise "Unsupported database type for backup: #{@db.service_type}" unless cmd
    "#{cmd} #{@db.name}"
  end

  def generate_s3_key(prefix)
    timestamp = Time.current.strftime("%Y-%m-%d_%H%M%S")
    # Legacy path: fleet-key AES blob (BackupCipher). Managed path: WKB1
    # envelope (EnvelopeCipher). Restores key off Backup#encrypted + magic
    # bytes, never the suffix — old .gz keys stay valid until the sweep.
    "#{prefix}/#{@db.service_type}/#{@db.name}/#{timestamp}.gz.enc"
  end
end
