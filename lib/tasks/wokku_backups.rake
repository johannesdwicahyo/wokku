namespace :wokku do
  namespace :backups do
    desc "Seed the platform-owned BackupDestination on every existing " \
         "Server (idempotent — servers that already have one are skipped)."
    task ensure_platform_destinations: :environment do
      seeded = 0
      skipped = 0
      Server.find_each do |server|
        if server.backup_destination.present?
          skipped += 1
        else
          server.ensure_platform_backup_destination
          server.reload
          if server.backup_destination.present?
            seeded += 1
            puts "  seeded: #{server.name} → #{server.backup_destination.bucket}/#{server.backup_destination.path_prefix}"
          else
            puts "  skipped (env not set?): #{server.name}"
          end
        end
      end
      puts "Done. seeded=#{seeded} already-configured=#{skipped}"
    end

    desc "Verify the platform destination is reachable by listing the " \
         "bucket root. Safe to run anytime."
    task verify_platform_destination: :environment do
      server = Server.joins(:backup_destination).first
      abort "No server has a BackupDestination. Run wokku:backups:ensure_platform_destinations first." unless server
      client = server.backup_destination.s3_client
      resp = client.list_objects_v2(bucket: server.backup_destination.bucket, max_keys: 1)
      puts "OK: bucket=#{server.backup_destination.bucket} " \
           "reachable (#{resp.key_count} object#{'s' unless resp.key_count == 1} sampled)"
    end
  end
end
