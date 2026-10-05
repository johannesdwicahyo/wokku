require "zlib"
require "shellwords"

# Weekly, non-destructive restore-drill: for one representative running DB per
# engine, restore its latest completed backup into a throwaway docker container
# (booted from the LIVE service's own image — guaranteed engine-version compat
# with the backup), compare table + row counts against live, then destroy the
# throwaway. Records a RestoreDrill audit row per engine and Sentry-alerts on
# failure. Per-engine failures are isolated — one engine blowing up never skips
# the rest, and nothing raises out of the scheduler.
#
# Productizes docs/runbooks/dr_restore_test.rb (live-verified on prod
# 2026-07-11: postgres, RTO 2.2s). The per-engine count SQL below generalizes
# that script's postgres pattern to mysql/mariadb/mongodb. W7 Phase 3: all
# host work rides Hosts::Ssh + docker — no dokku plugins.
class RestoreDrillJob < ApplicationJob
  queue_as :backups

  ENGINES = %w[postgres mysql mariadb mongodb redis].freeze

  # Hard ceiling on the raw Net::SSH channels below (stream_gunzip,
  # upload_and_untar) — these bypass Hosts::Ssh so they don't get its
  # timeout: kwarg for free; a wedged transfer must not pin the job forever.
  CHANNEL_TIMEOUT = 1800

  # Bounded wait for a freshly-run engine container to accept connections.
  ENGINE_BOOT_TIMEOUT = 120

  # engine -> minimal env its official image needs to boot. Throwaways run
  # with --network none (docker exec/cp need no network), so open/empty auth
  # is unreachable by anything but our root shell.
  # mariadb: MARIADB_* is current; the MYSQL_* aliases keep older adopted
  # images (which predate the MARIADB_ vars) booting too — extra env is inert.
  THROWAWAY_ENV = {
    "postgres" => { "POSTGRES_PASSWORD" => "drill" },
    "mysql"    => { "MYSQL_ALLOW_EMPTY_PASSWORD" => "yes", "MYSQL_DATABASE" => "drill" },
    "mariadb"  => { "MARIADB_ALLOW_EMPTY_ROOT_PASSWORD" => "1", "MARIADB_DATABASE" => "drill",
                    "MYSQL_ALLOW_EMPTY_PASSWORD" => "yes", "MYSQL_DATABASE" => "drill" },
    "mongodb"  => {},
    "redis"    => {}
  }.freeze

  # engine -> in-container readiness probe (run via `docker exec ... sh -c`).
  # mysql/mariadb poll over TCP (-h127.0.0.1) on purpose: the entrypoint's
  # socket-only init server answers the socket before the real (persistent)
  # server is up, and data imported into it gets wiped on its restart.
  READY_PROBES = {
    "postgres" => "pg_isready -U postgres",
    "mysql"    => "mysql -h127.0.0.1 -uroot -e 'SELECT 1'",
    "mariadb"  => "mariadb -h127.0.0.1 -uroot -e 'SELECT 1'",
    "mongodb"  => "mongosh --quiet --eval 'db.runCommand({ping:1}).ok'",
    "redis"    => "redis-cli PING"
  }.freeze

  # engine -> in-container client the gunzipped dump streams into
  # (`docker exec -i`). Mirrors wokkud's service.import executors
  # (RestoreService's managed path) against the throwaway's own env above:
  # postgres = local trust, mysql/mariadb = empty root pw into the `drill`
  # db, mongodump archives carry their own db name. redis has no stream
  # importer — see import_rdb (docker cp the RDB + restart).
  IMPORT_CLIENTS = {
    "postgres" => "psql -U postgres -d postgres",
    "mysql"    => "mysql -uroot drill",
    "mariadb"  => "mariadb -uroot drill",
    "mongodb"  => "mongorestore --archive"
  }.freeze

  # Database the restored data lands in inside the throwaway (what counts()
  # must connect to). mongodb falls back to the live dedicated_db_name —
  # mongorestore --archive restores into the origin db name. redis is dbless.
  THROWAWAY_DB = {
    "postgres" => "postgres",
    "mysql"    => "drill",
    "mariadb"  => "drill"
  }.freeze

  # Per-engine table-count + row-count queries. Each prints a literal MARK=/TBL=
  # prefix so we can regex the value out of noisy client output (banner lines,
  # column headers). postgres = verified in the runbook; sql engines use
  # information_schema (TABLE_ROWS is approximate for InnoDB — fine for a
  # "data present" check); mongodb counts collections + documents in mongosh.
  # ponytail: MySQL SUM(TABLE_ROWS) is approximate; the drill only asserts
  # rows>0 + table-count parity, so approximate is enough — swap to per-table
  # COUNT(*) only if a drill ever needs exact row parity.
  COUNT_QUERIES = {
    "postgres" => {
      tables: "SELECT 'TBL=' || count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';",
      rows: "SELECT 'MARK=' || COALESCE(sum(cnt),0) FROM (SELECT (xpath('/row/cnt/text()', query_to_xml(format('SELECT count(*) AS cnt FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint AS cnt FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE') t;"
    },
    "mysql" => {
      tables: "SELECT CONCAT('TBL=', COUNT(*)) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';",
      rows: "SELECT CONCAT('MARK=', COALESCE(SUM(TABLE_ROWS),0)) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';"
    },
    "mariadb" => {
      tables: "SELECT CONCAT('TBL=', COUNT(*)) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';",
      rows: "SELECT CONCAT('MARK=', COALESCE(SUM(TABLE_ROWS),0)) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';"
    },
    "mongodb" => {
      tables: "print('TBL=' + db.getCollectionNames().length)",
      rows: "var __t=0;db.getCollectionNames().forEach(function(c){__t+=db.getCollection(c).countDocuments({})});print('MARK='+__t)"
    },
    # redis has no tables — TBL is a constant so live/restored always match,
    # and the drill passes/fails on key count alone. Values are bare Lua
    # scripts fed to `redis-cli EVAL <script> 0`.
    # ponytail: DBSIZE counts db 0 only; per-numbered-db sums only if a
    # customer ever uses SELECT 1+ (everything defaults to db 0).
    "redis" => {
      tables: "return 'TBL=0'",
      rows: "return 'MARK='..redis.call('DBSIZE')"
    }
  }.freeze

  def perform
    ENGINES.each do |engine|
      db = representative_db(engine)
      next unless db

      # Skip if the host is already disk-pressured — a drill spins up a whole
      # throwaway container (extra disk); don't pile on a degraded box. Uses the
      # cached heartbeat vital (no SSH). See Server#record_heartbeat!.
      if disk_pressured?(db.server)
        Rails.logger.warn("RestoreDrillJob: skipping #{engine} drill — #{db.server.name} disk >= #{Server::DEGRADED_DISK_PCT}%")
        next
      end

      throwaway = "dr-verify-#{SecureRandom.hex(3)}"
      # Outer rescue: a secondary failure inside the inner rescue/ensure (e.g.
      # RestoreDrill.create! or Sentry.capture_message raising) must not escape
      # perform — that would skip the remaining engines. destroy_throwaway still
      # runs first via the inner ensure; this only catches what leaks past it.
      begin
        begin
          r = run_drill_restore(db, throwaway)
          # Empty live DB (e.g. a redis holding 0 keys) => rows>0 is unsatisfiable;
          # pass on table parity alone — same rule as the volume drill's live==0 case.
          passed = r[:restored_tables] == r[:live_tables] &&
            (r[:live_rows].to_i.zero? || r[:restored_rows].to_i.positive?)
          RestoreDrill.create!(
            engine: engine, database_service: db, backup: latest_completed_backup(db),
            status: passed ? :passed : :failed, **r
          )
          report_failure(engine, db, "counts mismatch: #{r.inspect}") unless passed
        rescue => e
          RestoreDrill.create!(engine: engine, database_service: db, status: :failed, error_message: e.message)
          report_failure(engine, db, e.message)
        ensure
          destroy_throwaway(db, throwaway)
        end
      rescue => e2
        Rails.logger.error("[RestoreDrillJob] #{engine}: secondary failure: #{e2.class}: #{e2.message}")
      end
    end

    # Weekly volume drill: one representative volume backup (newest completed
    # overall whose app still exists) — download + decrypt + untar into a
    # throwaway host dir, compare file count + total bytes vs the live mount,
    # then rm -rf the throwaway. Same double-rescue isolation as the DB engines:
    # nothing here can raise out of perform or affect the DB drills above.
    backup = representative_volume_backup
    if backup && disk_pressured?(backup.app_record.server)
      Rails.logger.warn("RestoreDrillJob: skipping volume drill — #{backup.app_record.server.name} disk >= #{Server::DEGRADED_DISK_PCT}%")
    elsif backup
      throwaway = "/tmp/dr-volume-#{SecureRandom.hex(6)}"
      begin
        begin
          r = run_volume_drill(backup, throwaway)
          restored_files = r[:restored_tables]
          live_files     = r[:live_tables]
          # PASS: restored dir has files AND is within ±20% of the live count
          # (a nonzero delta is expected churn, not a failure). If the live
          # mount couldn't be counted (live_files == 0), pass on restored alone.
          passed = restored_files.positive? &&
            (live_files.zero? || (restored_files - live_files).abs <= live_files * 0.2)
          # RestoreDrill column reuse (no volume-specific columns — YAGNI):
          # live/restored_tables hold FILE COUNTS, live/restored_rows hold BYTE
          # totals. Documented here so the numbers aren't misread as table/rows.
          RestoreDrill.create!(
            engine: "volume", backup: backup,
            status: passed ? :passed : :failed, **r
          )
          report_volume_failure(backup, "counts mismatch: #{r.inspect}") unless passed
        rescue => e
          RestoreDrill.create!(engine: "volume", backup: backup, status: :failed, error_message: e.message)
          report_volume_failure(backup, e.message)
        ensure
          destroy_volume_throwaway(throwaway, backup)
        end
      rescue => e2
        Rails.logger.error("[RestoreDrillJob] volume: secondary failure: #{e2.class}: #{e2.message}")
      end
    end
  end

  private

  # Post-sweep, DB backups are WKB1 envelopes; volume backups (and any
  # not-yet-swept blob) remain legacy fleet-key format — route by magic.
  # Returns a decrypted tempfile path the caller must unlink, or the input
  # path untouched when the backup isn't encrypted.
  def decrypt_backup(backup, path)
    return path unless backup.encrypted?

    if EnvelopeCipher.envelope?(path)
      EnvelopeCipher.decrypt_file(path, private_key: EnvelopeCipher.master_private_key)
    else
      BackupCipher.decrypt_file(path)
    end
  end

  # One representative running DB per engine (deterministic: oldest first) whose
  # latest backup is completed. Excludes shared-host infra rows via NULL-safe
  # IS DISTINCT FROM (the recurring shared_host-parent bug family), and shared
  # TENANTS: the drill counts/boots by container + dedicated_db_name, which
  # don't describe a tenant inside a parent (shared drill = follow-up).
  def representative_db(engine)
    DatabaseService
      .where(service_type: engine, status: :running, shared: false)
      .where("tier_name IS DISTINCT FROM 'shared_host'")
      .order(:created_at, :id)
      .find { |d| d.backups.completed.exists? }
  end

  def latest_completed_backup(db)
    db.backups.completed.order(created_at: :desc).first
  end

  def disk_pressured?(server)
    server.vitals.to_h["disk_used_pct"].to_f >= Server::DEGRADED_DISK_PCT
  end

  def report_failure(engine, db, msg)
    Sentry.capture_message("restore drill failed: #{engine}/#{db&.name}: #{msg}", level: :error)
  end

  # Real SSH. Ports docs/runbooks/dr_restore_test.rb, generalized per engine:
  # count live, boot a throwaway container from the live service's own image,
  # download + (decrypt) + import the latest completed backup into it (timing
  # RTO), count the restore. Specs stub this whole method.
  def run_drill_restore(db, throwaway)
    server = db.server
    ssh    = Hosts::Ssh.new(server)
    backup = latest_completed_backup(db)
    dest   = backup.backup_destination

    live_tables, live_rows = counts(ssh, db.service_type, db.container_name,
                                    db: db.dedicated_db_name, password: dsn_password(db))

    gz = dec_path = nil
    begin
      create_throwaway(ssh, db, throwaway)
      wait_for_engine(ssh, db.service_type, throwaway)

      gz = Tempfile.new([ "dr", ".gz" ], binmode: true)
      dest.s3_client.get_object(bucket: dest.bucket, key: backup.s3_key, response_target: gz.path)
      import_path = decrypt_backup(backup, gz.path)
      dec_path = import_path unless import_path == gz.path

      rto_ms = if db.service_type == "redis"
        import_rdb(server, ssh, throwaway, import_path)
      else
        import_dump(server, db.service_type, throwaway, import_path)
      end

      restored_tables, restored_rows = counts(ssh, db.service_type, throwaway,
                                              db: THROWAWAY_DB[db.service_type] || db.dedicated_db_name,
                                              password: nil)
      { live_tables: live_tables, live_rows: live_rows,
        restored_tables: restored_tables, restored_rows: restored_rows, rto_ms: rto_ms }
    ensure
      gz&.close
      gz&.unlink
      # Decrypted temp holds a plaintext dump — remove it on every path.
      File.unlink(dec_path) if dec_path && File.exist?(dec_path)
    end
  end

  # Boots the throwaway from the LIVE container's own image (docker inspect)
  # so the restore always meets a compatible engine version. --network none:
  # nothing else can ever reach the open/empty-auth throwaway.
  def create_throwaway(ssh, db, throwaway)
    image = ssh.run_raw("docker inspect -f '{{.Config.Image}}' #{Shellwords.escape(db.container_name)}", timeout: 30)
    env = THROWAWAY_ENV.fetch(db.service_type).map { |k, v| "-e #{k}=#{Shellwords.escape(v)}" }.join(" ")
    cmd = [ "docker run -d --network none --name #{Shellwords.escape(throwaway)}", env, Shellwords.escape(image) ]
      .reject(&:blank?).join(" ")
    ssh.run_raw(cmd, timeout: 300)
  end

  # Polls the engine's in-container readiness probe until it exits 0 —
  # bounded by ENGINE_BOOT_TIMEOUT so a broken image can't wedge the drill.
  def wait_for_engine(ssh, service_type, container)
    probe = "docker exec #{Shellwords.escape(container)} sh -c #{Shellwords.escape(READY_PROBES.fetch(service_type))}"
    deadline = Time.current + ENGINE_BOOT_TIMEOUT
    begin
      ssh.run_raw(probe, timeout: 30)
    rescue Hosts::Ssh::CommandError => e
      raise "throwaway #{container} (#{service_type}) not ready after #{ENGINE_BOOT_TIMEOUT}s: #{e.message}" if Time.current > deadline
      sleep 2
      retry
    end
  end

  # Streams the (decrypted) gzip dump into the engine client inside the
  # throwaway (`docker exec -i`), returning wall-clock RTO in ms.
  def import_dump(server, service_type, throwaway, gz_path)
    wire = "docker exec -i #{Shellwords.escape(throwaway)} #{IMPORT_CLIENTS.fetch(service_type)}"
    t0 = Time.current
    stream_gunzip(server, wire, gz_path)
    ((Time.current - t0) * 1000).round
  end

  # redis has no stdin importer — the docker equivalent of the old plugin RDB
  # import: land the raw RDB on the host, stop the throwaway, docker cp it
  # over /data/dump.rdb, start again (redis loads the RDB on boot). The whole
  # cycle is the RTO.
  def import_rdb(server, ssh, throwaway, gz_path)
    tmp = "/tmp/#{throwaway}.rdb"
    c = Shellwords.escape(throwaway)
    t0 = Time.current
    begin
      stream_gunzip(server, "cat > #{Shellwords.escape(tmp)}", gz_path)
      ssh.run_raw("docker stop #{c}", timeout: 60)
      ssh.run_raw("docker cp #{Shellwords.escape(tmp)} #{c}:/data/dump.rdb", timeout: 120)
      ssh.run_raw("docker start #{c}", timeout: 60)
      wait_for_engine(ssh, "redis", throwaway)
      ((Time.current - t0) * 1000).round
    ensure
      begin
        ssh.run_raw("rm -f #{Shellwords.escape(tmp)}", timeout: 30)
      rescue => e
        Rails.logger.warn("RestoreDrillJob: could not remove #{tmp}: #{e.message}")
      end
    end
  end

  # Root Net::SSH channel: gunzips gz_path locally while streaming the plain
  # bytes into `wire`'s stdin on the host. Mirrors RestoreService#perform!'s
  # import channel shape.
  def stream_gunzip(server, wire, gz_path)
    ssh_opts = { port: server.port || 22, non_interactive: true, timeout: 10 }
    ssh_opts[:key_data] = [ server.ssh_private_key ] if server.ssh_private_key.present?

    Timeout.timeout(CHANNEL_TIMEOUT) do
      Net::SSH.start(server.host, Hosts::Ssh.user, ssh_opts) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(wire) do |_ch, success|
            raise "Failed to execute #{wire}" unless success

            Zlib::GzipReader.open(gz_path) do |gz|
              while (chunk = gz.read(64 * 1024))
                ch.send_data(chunk)
              end
            end
            ch.eof!
            ch.on_extended_data { |_, _, data| Rails.logger.warn("RestoreDrillJob import stderr: #{data.to_s.strip}") }
          end
        end
        channel.wait
      end
    end
  end

  # Runs the per-engine count queries via `docker exec` (query passed as a
  # Shellwords-escaped argument — no stdin) and regexes TBL=/MARK= out of the
  # output. Live containers use their own credentials (mirrors
  # TerminalSession#db_connect_command); throwaways use the env we booted
  # them with (password: nil). Real SSH; specs stub run_drill_restore.
  def counts(ssh, service_type, container, db:, password:)
    q = COUNT_QUERIES.fetch(service_type)
    tables = ssh.run_raw(count_exec(service_type, container, db, password, q[:tables]), timeout: 60)[/TBL=(\d+)/, 1].to_i
    rows   = ssh.run_raw(count_exec(service_type, container, db, password, q[:rows]), timeout: 120)[/MARK=(\d+)/, 1].to_i
    [ tables, rows ]
  end

  def count_exec(service_type, container, db, password, query)
    c = Shellwords.escape(container)
    q = Shellwords.escape(query)
    case service_type
    when "postgres"
      "docker exec #{c} psql -U postgres -d #{Shellwords.escape(db)} -Atc #{q}"
    when "mysql", "mariadb"
      client = service_type == "mariadb" ? "mariadb" : "mysql"
      # MYSQL_PWD rides docker exec -e: visible in root's host ps only, never
      # in the container argv — same shape as TerminalSession#db_connect_command.
      env = password.present? ? "-e MYSQL_PWD=#{Shellwords.escape(password)} " : ""
      "docker exec #{env}#{c} #{client} -uroot -N #{Shellwords.escape(db)} -e #{q}"
    when "mongodb"
      auth = password.present? ? "-u root -p #{Shellwords.escape(password)} --authenticationDatabase admin " : ""
      "docker exec #{c} mongosh --quiet #{auth}#{Shellwords.escape(db)} --eval #{q}"
    when "redis"
      auth = password.present? ? "--no-auth-warning -a #{Shellwords.escape(password)} " : ""
      "docker exec #{c} redis-cli #{auth}EVAL #{q} 0"
    else
      raise ArgumentError, "no count client for #{service_type}"
    end
  end

  def dsn_password(db)
    db.dsn.presence && URI.parse(db.dsn).password
  end

  # Real SSH. Best-effort teardown in the perform `ensure`; a failure here can
  # only leak a throwaway, never affect the drill result — log it loudly so the
  # orphan gets cleaned up manually. -v also removes the anonymous data volume
  # the engine image declares.
  def destroy_throwaway(db, throwaway)
    Hosts::Ssh.new(db.server).run_raw("docker rm -fv #{Shellwords.escape(throwaway)}", timeout: 120)
  rescue => e
    Rails.logger.error("RestoreDrillJob: ORPHAN throwaway #{throwaway} on #{db.server&.name} not destroyed (clean up manually): #{e.message}")
    if defined?(Sentry)
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: "restore_drill", level: "error",
                                                   message: "orphan drill container #{throwaway}"))
    end
  end

  # Newest completed volume backup overall whose app_record still exists (a
  # destroyed app leaves the FK dangling -> app_record nil -> skip). nil when
  # there are none, and the volume drill is skipped silently.
  def representative_volume_backup
    Backup.kind_volume.where(status: "completed").order(created_at: :desc).detect { |b| b.app_record }
  end

  def report_volume_failure(backup, msg)
    Sentry.capture_message("restore drill failed: volume/#{backup&.app_record&.name}: #{msg}", level: :error)
  end

  # Real SSH. Downloads the tarball from R2, decrypts it, streams the bytes into
  # a root `tar -xzf -` on the host (no host tempfile), then counts restored
  # files/bytes and compares to the live mount. Specs stub this whole method.
  def run_volume_drill(backup, dir)
    server = backup.app_record.server
    ssh    = Hosts::Ssh.new(server)
    dest   = backup.backup_destination

    gz = dec_path = nil
    t0 = Time.current
    begin
      gz = Tempfile.new([ "dr-vol", ".tar.gz" ], binmode: true)
      dest.s3_client.get_object(bucket: dest.bucket, key: backup.s3_key, response_target: gz.path)
      tarball = decrypt_backup(backup, gz.path)
      dec_path = tarball unless tarball == gz.path

      upload_and_untar(server, tarball, dir)
      rto_ms = ((Time.current - t0) * 1000).round

      restored_files = dir_file_count(ssh, dir)
      restored_bytes = dir_byte_size(ssh, dir)

      # Live mount comparison is best-effort: re-validate mount_path against the
      # same STORAGE_ROOT anchor VolumeBackupService uses before it reaches a
      # root shell. If it fails, skip the live count — the drill still
      # passes/fails on restored_files alone (see the PASS gate in perform).
      live_files = live_bytes = 0
      mp = backup.mount_path
      if VolumeBackupService.safe_mount?(mp)
        live_files = dir_file_count(ssh, mp)
        live_bytes = dir_byte_size(ssh, mp)
      else
        Rails.logger.warn("RestoreDrillJob: volume drill live mount #{mp.inspect} failed anchor; comparing on restored counts only")
      end

      { live_tables: live_files, restored_tables: restored_files,
        live_rows: live_bytes, restored_rows: restored_bytes, rto_ms: rto_ms }
    ensure
      gz&.close
      gz&.unlink
      # Decrypted temp holds the plaintext tarball — remove it on every path.
      File.unlink(dec_path) if dec_path && File.exist?(dec_path)
    end
  end

  # Streams the (decrypted) .tar.gz bytes into a root `tar -xzf -` on the host,
  # extracting into `dir` (created first). Mirrors stream_gunzip's send_data-
  # over-channel transport, but feeds raw file bytes (tar does its own gunzip)
  # instead of a decompressed stream.
  def upload_and_untar(server, tarball_path, dir)
    wire = "mkdir -p #{Shellwords.escape(dir)} && tar -xzf - -C #{Shellwords.escape(dir)}"
    ssh_opts = { port: server.port || 22, non_interactive: true, timeout: 10 }
    ssh_opts[:key_data] = [ server.ssh_private_key ] if server.ssh_private_key.present?

    Timeout.timeout(CHANNEL_TIMEOUT) do
      Net::SSH.start(server.host, Hosts::Ssh.user, ssh_opts) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(wire) do |_ch, success|
            raise "Failed to execute #{wire}" unless success

            File.open(tarball_path, "rb") do |f|
              while (chunk = f.read(64 * 1024))
                ch.send_data(chunk)
              end
            end
            ch.eof!
            ch.on_extended_data { |_, _, data| Rails.logger.warn("RestoreDrillJob untar stderr: #{data.to_s.strip}") }
          end
        end
        channel.wait
      end
    end
  end

  # Root-shell file count / byte total for a host dir. Shellwords.escape'd
  # regardless of the anchor check (defense in depth). run_raw output is
  # already stripped; to_i tolerates trailing whitespace.
  def dir_file_count(ssh, dir)
    ssh.run_raw("find #{Shellwords.escape(dir)} -type f | wc -l", timeout: 120).to_i
  end

  def dir_byte_size(ssh, dir)
    # 600s: cold large mounts can take a while for du to walk.
    ssh.run_raw("du -sb #{Shellwords.escape(dir)} | cut -f1", timeout: 600).to_i
  end

  # Best-effort teardown in the perform `ensure`. SECURITY: never rm -rf a path
  # that isn't a throwaway we generated — validate the anchor first, refuse
  # (log, return) on any mismatch. Self-rescues so a teardown failure can only
  # leak a dir, never affect the drill result.
  def destroy_volume_throwaway(path, backup)
    unless path.is_a?(String) && path.match?(%r{\A/tmp/dr-volume-[0-9a-f]+(\.tar\.gz)?\z})
      Rails.logger.error("RestoreDrillJob: refusing rm -rf on unvalidated throwaway path #{path.inspect}")
      return
    end
    server = backup&.app_record&.server
    return unless server

    Hosts::Ssh.new(server).run_raw("rm -rf #{Shellwords.escape(path)}", timeout: 60)
  rescue => e
    Rails.logger.error("RestoreDrillJob: ORPHAN volume throwaway #{path} not destroyed (clean up manually): #{e.message}")
    if defined?(Sentry)
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: "restore_drill", level: "error",
                                                   message: "orphan drill dir #{path}"))
    end
  end
end
