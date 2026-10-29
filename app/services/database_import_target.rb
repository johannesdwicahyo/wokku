# Where a wokkud service.import lands for a DatabaseService: the service that
# owns the container (a shared tenant's parent), the database inside it, and
# the password to send. Shared by RestoreService (backups) and ImportService
# (user-uploaded dumps). Expects @db.
module DatabaseImportTarget
  private

  def managed_op_service
    @db.shared? ? @db.parent_service : @db
  end

  def managed_op_database
    @db.shared? ? @db.shared_db_name : @db.dedicated_db_name
  end

  # A shared tenant's DSN holds the TENANT's password, not the parent's
  # root one — send none: postgres dumps as the local superuser, mariadb
  # reads the root password from the parent container's env (wokkud).
  def dsn_password
    return nil if @db.shared?
    @db.dsn.present? ? URI.parse(@db.dsn).password : nil
  end
end
