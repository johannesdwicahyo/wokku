# One-off B4 sweep: converts every completed managed-DB backup object in R2
# to the WKB1 envelope — plaintext .gz (pre-B4 managed path) and legacy
# fleet-key .gz.enc (pre-adoption SSH path, unrestorable on the managed path
# today) alike. Idempotent: envelope objects are detected by magic and
# skipped, so re-runs and interrupted runs are safe. The old object is only
# deleted after the new upload and record update succeed.
class BackupReencryptSweep
  def self.call
    swept = skipped = failed = 0
    Backup.completed.includes(:database_service, :backup_destination).find_each do |backup|
      next if backup.kind_volume?
      db = backup.database_service
      # db is nil for a detached farewell snapshot (the owning DB was
      # destroyed and the row FK-detached, see commit a9cea1bc) — those
      # still need sweeping, they just have no service to check managed-ness.
      next unless db.nil? || db.wokkud_managed?

      case sweep_one(backup, db)
      when :swept then swept += 1
      when :skipped then skipped += 1
      else failed += 1
      end
    end
    { swept: swept, skipped: skipped, failed: failed }
  end

  def self.sweep_one(backup, db)
    dest = backup.backup_destination
    raw = Tempfile.create([ "sweep", ".bin" ])
    raw.binmode
    raw.close
    plain_path = enc_path = nil

    dest.s3_client.get_object(bucket: dest.bucket, key: backup.s3_key, response_target: raw.path)
    return :skipped if EnvelopeCipher.envelope?(raw.path)

    plain_path = backup.encrypted? ? BackupCipher.decrypt_file(raw.path) : raw.path
    enc_path = EnvelopeCipher.encrypt_file(plain_path, public_key: EnvelopeCipher.public_key_pem)

    old_key = backup.s3_key
    new_key = backup.encrypted? ? old_key : "#{old_key}.enc"
    File.open(enc_path, "rb") do |f|
      dest.s3_client.put_object(bucket: dest.bucket, key: new_key, body: f, content_type: "application/octet-stream")
    end
    backup.update!(s3_key: new_key, encrypted: true, size_bytes: File.size(enc_path))
    # The record is already correct at this point — a delete failure here
    # must not be miscounted as :failed (that would imply the record is
    # wrong and worth retrying; it isn't, the plaintext object is just
    # orphaned). Log it loudly and distinctly so it can be grepped and
    # deleted by hand instead.
    if old_key != new_key
      begin
        dest.s3_client.delete_object(bucket: dest.bucket, key: old_key)
      rescue => e
        Rails.logger.error("[BackupReencryptSweep] ORPHANED plaintext object left at #{old_key} — delete manually: #{e.message}")
      end
    end
    Rails.logger.info("[BackupReencryptSweep] swept #{db&.name || "detached"} #{new_key}")
    :swept
  rescue => e
    Rails.logger.error("[BackupReencryptSweep] FAILED (left untouched) #{db&.name || "detached"} #{backup.s3_key}: #{e.message}")
    :failed
  ensure
    [ raw&.path, plain_path, enc_path ].compact.uniq.each do |p|
      File.unlink(p) if File.exist?(p)
    end
  end
  private_class_method :sweep_one
end
