require "rails_helper"

RSpec.describe RestoreDrillJob do
  it "records a passed drill and destroys the throwaway when restore verifies" do
    db = create(:database_service, service_type: "postgres", status: :running)
    create(:backup, database_service: db, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) { |engine| engine == "postgres" ? db : nil }
    allow(job).to receive(:run_drill_restore).and_return(
      { live_tables: 5, live_rows: 100, restored_tables: 5, restored_rows: 98, rto_ms: 2200 }
    )
    destroyed = []
    allow(job).to receive(:destroy_throwaway) { |_db, name| destroyed << name }

    expect { job.perform }.to change(RestoreDrill.passed, :count).by(1)
    expect(destroyed).not_to be_empty
    drill = RestoreDrill.passed.last
    expect(drill.engine).to eq("postgres")
    expect(drill.backup).to eq(db.backups.completed.first)
    expect(drill.rto_ms).to eq(2200)
  end

  it "records a failed drill when counts mismatch (restored has zero rows)" do
    db = create(:database_service, service_type: "postgres", status: :running)
    create(:backup, database_service: db, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) { |engine| engine == "postgres" ? db : nil }
    allow(job).to receive(:run_drill_restore).and_return(
      { live_tables: 5, live_rows: 100, restored_tables: 5, restored_rows: 0, rto_ms: 100 }
    )
    allow(job).to receive(:destroy_throwaway)
    expect(Sentry).to receive(:capture_message).with(/restore drill failed/i, hash_including(level: :error))

    expect { job.perform }.to change(RestoreDrill.failed, :count).by(1)
  end

  it "passes when the live DB is empty (0 rows live and restored, e.g. an empty redis)" do
    db = create(:database_service, service_type: "redis", status: :running)
    create(:backup, database_service: db, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) { |engine| engine == "redis" ? db : nil }
    allow(job).to receive(:run_drill_restore).and_return(
      { live_tables: 0, live_rows: 0, restored_tables: 0, restored_rows: 0, rto_ms: 900 }
    )
    allow(job).to receive(:destroy_throwaway)
    expect(Sentry).not_to receive(:capture_message)

    expect { job.perform }.to change(RestoreDrill.passed, :count).by(1)
  end

  it "records failed + reports to Sentry when a restore verify raises, without aborting other engines" do
    db = create(:database_service, service_type: "mariadb", status: :running)
    create(:backup, database_service: db, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) { |engine| engine == "mariadb" ? db : nil }
    allow(job).to receive(:run_drill_restore).and_raise("import blew up")
    destroyed = []
    allow(job).to receive(:destroy_throwaway) { |_db, name| destroyed << name }
    expect(Sentry).to receive(:capture_message).with(/restore drill failed/i, hash_including(level: :error))

    expect { job.perform }.to change(RestoreDrill.failed, :count).by(1)
    # throwaway still torn down even though the restore raised
    expect(destroyed).not_to be_empty
  end

  it "isolates per-engine failures: one engine raising does not skip the others" do
    pg = create(:database_service, service_type: "postgres", status: :running)
    create(:backup, database_service: pg, status: "completed")
    maria = create(:database_service, service_type: "mariadb", status: :running)
    create(:backup, database_service: maria, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) do |engine|
      { "postgres" => pg, "mariadb" => maria }[engine]
    end
    allow(job).to receive(:destroy_throwaway)
    allow(Sentry).to receive(:capture_message)
    allow(job).to receive(:run_drill_restore) do |db, _throwaway|
      raise "postgres boom" if db == pg
      { live_tables: 3, live_rows: 9, restored_tables: 3, restored_rows: 9, rto_ms: 50 }
    end

    expect { job.perform }.to change(RestoreDrill, :count).by(2)
    expect(RestoreDrill.failed.count).to eq(1) # postgres
    expect(RestoreDrill.passed.count).to eq(1) # mariadb still ran
  end

  it "survives a secondary failure in the rescue path (RestoreDrill.create! raising) and still processes the next engine" do
    pg = create(:database_service, service_type: "postgres", status: :running)
    create(:backup, database_service: pg, status: "completed")
    maria = create(:database_service, service_type: "mariadb", status: :running)
    create(:backup, database_service: maria, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) do |engine|
      { "postgres" => pg, "mariadb" => maria }[engine]
    end
    allow(job).to receive(:destroy_throwaway)
    allow(job).to receive(:run_drill_restore) do |db, _throwaway|
      raise "postgres boom" if db == pg
      { live_tables: 3, live_rows: 9, restored_tables: 3, restored_rows: 9, rto_ms: 50 }
    end
    # Primary failure for postgres triggers the rescue path; RestoreDrill.create!
    # inside that rescue path blows up too (e.g. a DB hiccup).
    allow(RestoreDrill).to receive(:create!).and_wrap_original do |original, **kwargs|
      raise "create! blew up too" if kwargs[:engine] == "postgres"
      original.call(**kwargs)
    end
    expect(Rails.logger).to receive(:error).with(/RestoreDrillJob.*postgres.*secondary failure/)

    expect { job.perform }.not_to raise_error
    expect(RestoreDrill.count).to eq(1) # mariadb still recorded
    expect(RestoreDrill.passed.count).to eq(1)
  end

  it "drills a shared tenant as its own '<engine>-shared' row" do
    parent = create(:database_service, service_type: "postgres", status: :running, tier_name: "shared_host",
                                       name: "dokku-shared-postgres")
    tenant = create(:database_service, service_type: "postgres", status: :running, shared: true,
                                       tier_name: "shared_free", parent_service: parent, server: parent.server)
    create(:backup, database_service: tenant, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db).and_return(nil)
    allow(job).to receive(:representative_shared_tenant) { |engine| engine == "postgres" ? tenant : nil }
    allow(job).to receive(:run_drill_restore).and_return(
      { live_tables: 2, live_rows: 7, restored_tables: 2, restored_rows: 7, rto_ms: 300 }
    )
    allow(job).to receive(:destroy_throwaway)

    expect { job.perform }.to change(RestoreDrill.passed, :count).by(1)
    expect(RestoreDrill.passed.last).to have_attributes(engine: "postgres-shared", database_service: tenant)
  end

  it "skips a drill when the host disk is under pressure" do
    db = create(:database_service, service_type: "postgres", status: :running)
    db.server.update!(vitals: { "disk_used_pct" => 95 })
    create(:backup, database_service: db, status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db) { |engine| engine == "postgres" ? db : nil }
    expect(job).not_to receive(:run_drill_restore)

    expect { job.perform }.not_to change(RestoreDrill, :count)
  end

  describe "#representative_db" do
    let(:job) { described_class.new }

    it "picks the oldest running db of the engine that has a completed backup" do
      newer = create(:database_service, service_type: "postgres", status: :running, created_at: 1.day.ago)
      create(:backup, database_service: newer, status: "completed")
      older = create(:database_service, service_type: "postgres", status: :running, created_at: 3.days.ago)
      create(:backup, database_service: older, status: "completed")

      expect(job.send(:representative_db, "postgres")).to eq(older)
    end

    it "excludes shared_host infra rows" do
      infra = create(:database_service, service_type: "postgres", status: :running,
                                        tier_name: "shared_host", created_at: 5.days.ago)
      create(:backup, database_service: infra, status: "completed")
      real = create(:database_service, service_type: "postgres", status: :running, created_at: 1.day.ago)
      create(:backup, database_service: real, status: "completed")

      expect(job.send(:representative_db, "postgres")).to eq(real)
    end

    it "excludes shared tenants (they drill separately via representative_shared_tenant)" do
      parent = create(:database_service, service_type: "mariadb", status: :running, tier_name: "shared_host",
                                         name: "dokku-shared-mariadb", created_at: 6.days.ago)
      tenant = create(:database_service, service_type: "mariadb", status: :running, shared: true,
                                         tier_name: "shared_free", parent_service: parent, created_at: 5.days.ago)
      create(:backup, database_service: tenant, status: "completed")
      real = create(:database_service, service_type: "mariadb", status: :running, created_at: 1.day.ago)
      create(:backup, database_service: real, status: "completed")

      expect(job.send(:representative_db, "mariadb")).to eq(real)
    end

    it "representative_shared_tenant picks a backed-up running tenant, never the parent" do
      parent = create(:database_service, service_type: "mariadb", status: :running, tier_name: "shared_host",
                                         name: "dokku-shared-mariadb", created_at: 6.days.ago)
      create(:backup, database_service: parent, status: "completed")
      tenant = create(:database_service, service_type: "mariadb", status: :running, shared: true,
                                         tier_name: "shared_free", parent_service: parent, created_at: 5.days.ago)
      create(:backup, database_service: tenant, status: "completed")

      expect(job.send(:representative_shared_tenant, "mariadb")).to eq(tenant)
    end

    it "skips dbs without a completed backup" do
      no_backup = create(:database_service, service_type: "postgres", status: :running, created_at: 5.days.ago)
      create(:backup, database_service: no_backup, status: "running") # in-flight, not completed
      good = create(:database_service, service_type: "postgres", status: :running, created_at: 1.day.ago)
      create(:backup, database_service: good, status: "completed")

      expect(job.send(:representative_db, "postgres")).to eq(good)
    end

    it "ignores non-running dbs" do
      stopped = create(:database_service, service_type: "postgres", status: :stopped, created_at: 5.days.ago)
      create(:backup, database_service: stopped, status: "completed")

      expect(job.send(:representative_db, "postgres")).to be_nil
    end
  end

  describe "volume drill" do
    it "records a passed volume drill and destroys the throwaway dir" do
      app = create(:app_record)
      create(:backup, :volume, app_record: app,
             mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
      job = described_class.new
      allow(job).to receive(:representative_db).and_return(nil)   # skip DB engines
      allow(job).to receive(:run_volume_drill).and_return(
        { live_tables: 120, restored_tables: 118, live_rows: 52_000_000, restored_rows: 51_800_000, rto_ms: 900 }
      )
      destroyed = []
      allow(job).to receive(:destroy_volume_throwaway) { |name| destroyed << name }

      expect { job.perform }.to change(RestoreDrill.passed.where(engine: "volume"), :count).by(1)
      expect(destroyed).not_to be_empty
    end

    it "records failed + Sentry on a volume drill error without raising" do
      app = create(:app_record)
      create(:backup, :volume, app_record: app,
             mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
      job = described_class.new
      allow(job).to receive(:representative_db).and_return(nil)
      allow(job).to receive(:run_volume_drill).and_raise("untar blew up")
      allow(job).to receive(:destroy_volume_throwaway)
      expect(Sentry).to receive(:capture_message).with(/restore drill failed: volume/i, anything)

      expect { job.perform }.not_to raise_error
      expect(RestoreDrill.failed.where(engine: "volume").count).to eq(1)
    end

    it "skips the volume drill when no volume backups exist" do
      job = described_class.new
      allow(job).to receive(:representative_db).and_return(nil)
      expect(job).not_to receive(:run_volume_drill)
      job.perform
    end

    it "skips the volume drill when the host disk is under pressure" do
      app = create(:app_record)
      app.server.update!(vitals: { "disk_used_pct" => 95 })
      create(:backup, :volume, app_record: app,
             mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
      job = described_class.new
      allow(job).to receive(:representative_db).and_return(nil)
      expect(job).not_to receive(:run_volume_drill)

      expect { job.perform }.not_to change(RestoreDrill, :count)
    end

    describe "#destroy_volume_throwaway rm -rf refusal guard" do
      let(:app) { create(:app_record) }
      let(:backup) do
        create(:backup, :volume, app_record: app,
               mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
      end
      let(:job) { described_class.new }

      it "refuses unvalidated paths — never constructs a transport or runs rm" do
        expect(Hosts::Ssh).not_to receive(:new)
        bad = [ "/etc", "/tmp/dr-volume-../../../etc", "/tmp/dr-volume-abc; rm -rf /",
                "/tmp/dr-volume-", "/var/lib/dokku/data/storage/x", nil ]
        expect(Rails.logger).to receive(:error).with(/refusing rm -rf/).exactly(bad.size).times

        bad.each { |path| job.send(:destroy_volume_throwaway, path, backup) }
      end

      it "proceeds on a valid throwaway path — run_raw receives the rm command" do
        ssh = instance_double(Hosts::Ssh)
        allow(Hosts::Ssh).to receive(:new).with(app.server).and_return(ssh)
        expect(ssh).to receive(:run_raw).with("rm -rf /tmp/dr-volume-abc123", timeout: 60)

        job.send(:destroy_volume_throwaway, "/tmp/dr-volume-abc123", backup)
      end
    end
  end

  describe "docker wire commands" do
    let(:job) { described_class.new }

    describe "#count_exec" do
      it "postgres: psql -Atc against the given db, no password" do
        cmd = job.send(:count_exec, "postgres", "dokku.postgres.mydb", "my_db", nil, "SELECT 1;")
        expect(cmd).to eq("docker exec dokku.postgres.mydb psql -U postgres -d my_db -Atc SELECT\\ 1\\;")
      end

      it "mysql: rides MYSQL_PWD via docker exec -e when a password is present" do
        cmd = job.send(:count_exec, "mysql", "c", "drill", "s3cr3t", "SELECT 1;")
        expect(cmd).to include("docker exec -e MYSQL_PWD=s3cr3t c mysql -uroot -N drill -e")
      end

      it "mariadb: uses the mariadb client and no -e env without a password" do
        cmd = job.send(:count_exec, "mariadb", "c", "drill", nil, "SELECT 1;")
        expect(cmd).to start_with("docker exec c mariadb -uroot -N drill -e")
      end

      it "mariadb shared parent: reads root's password from the container env, never the argv" do
        cmd = job.send(:count_exec, "mariadb", "dokku-shared-mariadb", "shop", :container_env, "SELECT 1;")
        expect(cmd).to start_with("docker exec dokku-shared-mariadb sh -c ")
        expect(cmd).to include("\\$MARIADB_ROOT_PASSWORD")
        expect(cmd).to end_with(" sh shop SELECT\\ 1\\;")
      end

      it "mongodb: authenticates against admin only when a password is present" do
        with_pw = job.send(:count_exec, "mongodb", "c", "appdb", "pw", "print(1)")
        expect(with_pw).to include("mongosh --quiet -u root -p pw --authenticationDatabase admin appdb --eval")
        without = job.send(:count_exec, "mongodb", "c", "appdb", nil, "print(1)")
        expect(without).to include("mongosh --quiet appdb --eval")
      end

      it "redis: EVALs the lua script, with -a only when a password is present" do
        with_pw = job.send(:count_exec, "redis", "c", "ignored", "pw", "return 'TBL=0'")
        expect(with_pw).to include("redis-cli --no-auth-warning -a pw EVAL")
        without = job.send(:count_exec, "redis", "c", "ignored", nil, "return 'TBL=0'")
        expect(without).to include("redis-cli EVAL")
        expect(without).to end_with(" 0")
      end

      it "escapes hostile input before it reaches the root shell" do
        cmd = job.send(:count_exec, "postgres", "c; rm -rf /", "db$(reboot)", nil, "q")
        expect(cmd).not_to match(/(?<!\\)[;$]/)
      end
    end

    describe "#create_throwaway" do
      it "boots the throwaway from the live container's image with --network none and the engine env" do
        db = create(:database_service, service_type: "postgres", status: :running)
        ssh = instance_double(Hosts::Ssh)
        ran = []
        allow(ssh).to receive(:run_raw) { |cmd, **| ran << cmd; "postgres:16" }

        job.send(:create_throwaway, ssh, db, "dr-verify-abc123")

        expect(ran.first).to eq("docker inspect -f '{{.Config.Image}}' #{db.container_name}")
        expect(ran.last).to eq("docker run -d --network none --name dr-verify-abc123 -e POSTGRES_PASSWORD=drill postgres:16")
      end

      it "boots env-less engines (mongodb) without -e flags" do
        db = create(:database_service, service_type: "mongodb", status: :running)
        ssh = instance_double(Hosts::Ssh)
        allow(ssh).to receive(:run_raw).and_return("mongo:7")

        expect(ssh).to receive(:run_raw)
          .with("docker inspect -f '{{.Config.Image}}' #{db.container_name}", timeout: 30).ordered.and_return("mongo:7")
        expect(ssh).to receive(:run_raw)
          .with("docker run -d --network none --name dr-verify-abc123 mongo:7", timeout: 300).ordered

        job.send(:create_throwaway, ssh, db, "dr-verify-abc123")
      end
    end

    describe "#destroy_throwaway" do
      it "docker rm -fv's the throwaway (anonymous volume included)" do
        db = create(:database_service, service_type: "redis", status: :running)
        ssh = instance_double(Hosts::Ssh)
        allow(Hosts::Ssh).to receive(:new).with(db.server).and_return(ssh)
        expect(ssh).to receive(:run_raw).with("docker rm -fv dr-verify-abc123", timeout: 120)

        job.send(:destroy_throwaway, db, "dr-verify-abc123")
      end

      it "logs the orphan loudly instead of raising when teardown fails" do
        db = create(:database_service, service_type: "redis", status: :running)
        ssh = instance_double(Hosts::Ssh)
        allow(Hosts::Ssh).to receive(:new).and_return(ssh)
        allow(ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError.new("boom"))
        expect(Rails.logger).to receive(:error).with(/ORPHAN throwaway dr-verify-abc123/)

        expect { job.send(:destroy_throwaway, db, "dr-verify-abc123") }.not_to raise_error
      end
    end

    it "IMPORT_CLIENTS mirror the managed restore executors (no dokku plugins)" do
      expect(described_class::IMPORT_CLIENTS).to eq(
        "postgres" => "psql -U postgres -d postgres",
        "mysql"    => "mysql -uroot drill",
        "mariadb"  => "mariadb -uroot drill",
        "mongodb"  => "mongorestore --archive"
      )
    end
  end

  describe "#decrypt_backup" do
    let(:job) { described_class.new }
    let(:test_key) { OpenSSL::PKey::RSA.new(File.read(Rails.root.join("spec/fixtures/envelope/test_key.pem"))) }

    it "returns the path untouched for unencrypted backups" do
      backup = Backup.new(encrypted: false)
      expect(job.send(:decrypt_backup, backup, "/tmp/x.gz")).to eq("/tmp/x.gz")
    end

    it "routes WKB1 blobs to EnvelopeCipher" do
      allow(EnvelopeCipher).to receive(:master_private_key).and_return(test_key)
      plain = Tempfile.create("p"); plain.write("drill-payload"); plain.close
      enc = EnvelopeCipher.encrypt_file(plain.path, public_key: test_key.public_key)

      dec = job.send(:decrypt_backup, Backup.new(encrypted: true), enc)

      expect(File.binread(dec)).to eq("drill-payload")
    ensure
      [ enc, dec ].compact.each { |p| File.unlink(p) if File.exist?(p) }
    end

    it "routes legacy blobs to BackupCipher" do
      backup = Backup.new(encrypted: true)
      legacy = Tempfile.create("l"); legacy.binmode; legacy.write("\x00" * 64); legacy.close
      expect(BackupCipher).to receive(:decrypt_file).with(legacy.path).and_return("/tmp/dec.gz")

      expect(job.send(:decrypt_backup, backup, legacy.path)).to eq("/tmp/dec.gz")
    end
  end

  it "survives a secondary failure in the volume rescue path (RestoreDrill.create! raising)" do
    app = create(:app_record)
    create(:backup, :volume, app_record: app,
           mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
    job = described_class.new
    allow(job).to receive(:representative_db).and_return(nil)
    allow(job).to receive(:run_volume_drill).and_raise("untar blew up")
    allow(job).to receive(:destroy_volume_throwaway)
    allow(RestoreDrill).to receive(:create!).and_raise("db down too")
    expect(Rails.logger).to receive(:error).with(/RestoreDrillJob.*volume: secondary failure/)

    expect { job.perform }.not_to raise_error
    # throwaway teardown still ran via the inner ensure
    expect(job).to have_received(:destroy_volume_throwaway)
  end

  describe "#run_drill_restore (stubbed transports)" do
    let(:job) { described_class.new }

    # ssh.run_raw stub answering the count queries: the tables query embeds a
    # literal TBL=, the rows query a literal MARK=.
    def counting_ssh
      ssh = instance_double(Hosts::Ssh)
      allow(ssh).to receive(:run_raw) do |cmd, **|
        # the wire command is Shellwords-escaped, so the literal is TBL\=
        cmd.include?("TBL") ? "TBL=5" : "MARK=100"
      end
      ssh
    end

    def stub_s3_download(backup, bytes)
      dest = backup.backup_destination
      s3 = double("s3")
      allow(dest).to receive(:s3_client).and_return(s3)
      allow(s3).to receive(:get_object) do |bucket:, key:, response_target:|
        expect(bucket).to eq(dest.bucket)
        expect(key).to eq(backup.s3_key)
        File.binwrite(response_target, bytes)
      end
    end

    it "counts live, boots + waits on the throwaway, downloads + decrypts + imports, counts restored, unlinks the decrypted temp" do
      db = create(:database_service, service_type: "postgres", status: :running,
                                     dsn: "postgres://wokku:s3cret@10.0.0.9:5432/mydb")
      backup = create(:backup, database_service: db, status: "completed")
      allow(Hosts::Ssh).to receive(:new).with(db.server).and_return(counting_ssh)
      allow(job).to receive(:latest_completed_backup).and_return(backup)
      stub_s3_download(backup, "gz-bytes")

      dec = Tempfile.create("dec"); dec.write("plain"); dec.close
      allow(job).to receive(:decrypt_backup).and_return(dec.path)
      allow(job).to receive(:create_throwaway)
      allow(job).to receive(:wait_for_engine)
      expect(job).to receive(:import_dump)
        .with(db.server, "postgres", "dr-verify-x", dec.path).and_return(1234)

      r = job.send(:run_drill_restore, db, "dr-verify-x")

      expect(r).to eq(live_tables: 5, live_rows: 100,
                      restored_tables: 5, restored_rows: 100, rto_ms: 1234)
      expect(job).to have_received(:create_throwaway)
      expect(job).to have_received(:wait_for_engine).with(anything, "postgres", "dr-verify-x")
      # decrypted plaintext dump removed on the way out
      expect(File.exist?(dec.path)).to be(false)
    end

    it "counts a shared tenant live in its PARENT's container, by tenant db name, with the parent's credentials" do
      parent = create(:database_service, service_type: "mariadb", status: :running, tier_name: "shared_host",
                                         name: "dokku-shared-mariadb")
      tenant = create(:database_service, service_type: "mariadb", status: :running, shared: true, tier_name: "shared_free",
                                         parent_service: parent, server: parent.server, shared_db_name: "shop",
                                         dsn: "mysql://shop:tenantpw@dokku-shared-mariadb:3306/shop")
      backup = create(:backup, database_service: tenant, status: "completed")
      allow(Hosts::Ssh).to receive(:new).and_return(counting_ssh)
      allow(job).to receive(:latest_completed_backup).and_return(backup)
      stub_s3_download(backup, "gz")
      allow(job).to receive(:decrypt_backup) { |_b, path| path }
      allow(job).to receive(:create_throwaway)
      allow(job).to receive(:wait_for_engine)
      allow(job).to receive(:import_dump).and_return(10)
      expect(job).to receive(:counts)
        .with(anything, "mariadb", "dokku-shared-mariadb", db: "shop", password: :container_env).and_return([ 1, 1 ])
      expect(job).to receive(:counts)
        .with(anything, "mariadb", "dr-verify-s", db: "drill", password: nil).and_return([ 1, 1 ])

      job.send(:run_drill_restore, tenant, "dr-verify-s")
    end

    it "routes redis through import_rdb instead of import_dump" do
      db = create(:database_service, service_type: "redis", status: :running)
      backup = create(:backup, database_service: db, status: "completed")
      allow(Hosts::Ssh).to receive(:new).with(db.server).and_return(counting_ssh)
      allow(job).to receive(:latest_completed_backup).and_return(backup)
      stub_s3_download(backup, "rdb-gz")
      allow(job).to receive(:create_throwaway)
      allow(job).to receive(:wait_for_engine)
      expect(job).not_to receive(:import_dump)
      expect(job).to receive(:import_rdb).and_return(900)

      r = job.send(:run_drill_restore, db, "dr-verify-r")

      expect(r[:rto_ms]).to eq(900)
    end
  end

  describe "#wait_for_engine" do
    let(:job) { described_class.new }

    it "returns once the readiness probe exits 0" do
      ssh = instance_double(Hosts::Ssh)
      expect(ssh).to receive(:run_raw)
        .with("docker exec tw sh -c #{Shellwords.escape(described_class::READY_PROBES.fetch('postgres'))}", timeout: 30)
        .and_return("accepting connections")

      expect { job.send(:wait_for_engine, ssh, "postgres", "tw") }.not_to raise_error
    end

    it "sleeps and retries while the probe fails within the deadline" do
      ssh = instance_double(Hosts::Ssh)
      calls = 0
      allow(ssh).to receive(:run_raw) do
        calls += 1
        raise Hosts::Ssh::CommandError, "not ready" if calls == 1
        "ok"
      end
      expect(job).to receive(:sleep).with(2)

      job.send(:wait_for_engine, ssh, "redis", "tw")
      expect(calls).to eq(2)
    end

    it "raises once the boot deadline passes" do
      ssh = instance_double(Hosts::Ssh)
      allow(ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError, "still down")
      t0 = Time.current
      allow(Time).to receive(:current).and_return(t0, t0 + described_class::ENGINE_BOOT_TIMEOUT + 60)
      allow(job).to receive(:sleep)

      expect { job.send(:wait_for_engine, ssh, "mysql", "tw") }
        .to raise_error(/tw \(mysql\) not ready after #{described_class::ENGINE_BOOT_TIMEOUT}s/)
    end
  end

  describe "#import_dump" do
    it "streams the dump into the engine client and returns wall-clock ms" do
      job = described_class.new
      server = create(:server)
      expect(job).to receive(:stream_gunzip)
        .with(server, "docker exec -i tw psql -U postgres -d postgres", "/tmp/d.gz")

      expect(job.send(:import_dump, server, "postgres", "tw", "/tmp/d.gz")).to be_a(Integer)
    end
  end

  describe "#import_rdb" do
    let(:job) { described_class.new }
    let(:server) { create(:server) }

    it "lands the RDB, stop/cp/start cycles the throwaway, waits for redis, and removes the host temp" do
      ssh = instance_double(Hosts::Ssh)
      allow(job).to receive(:stream_gunzip)
        .with(server, "cat > /tmp/tw.rdb", "/tmp/r.gz")
      allow(job).to receive(:wait_for_engine).with(ssh, "redis", "tw")
      expect(ssh).to receive(:run_raw).with("docker stop tw", timeout: 60).ordered
      expect(ssh).to receive(:run_raw).with("docker cp /tmp/tw.rdb tw:/data/dump.rdb", timeout: 120).ordered
      expect(ssh).to receive(:run_raw).with("docker start tw", timeout: 60).ordered
      expect(ssh).to receive(:run_raw).with("rm -f /tmp/tw.rdb", timeout: 30).ordered

      expect(job.send(:import_rdb, server, ssh, "tw", "/tmp/r.gz")).to be_a(Integer)
    end

    it "only warns when the host temp cannot be removed" do
      ssh = instance_double(Hosts::Ssh)
      allow(job).to receive(:stream_gunzip)
      allow(job).to receive(:wait_for_engine)
      allow(ssh).to receive(:run_raw) do |cmd, **|
        raise Hosts::Ssh::CommandError, "rm denied" if cmd.start_with?("rm -f")
        ""
      end
      expect(Rails.logger).to receive(:warn).with(%r{could not remove /tmp/tw\.rdb})

      expect(job.send(:import_rdb, server, ssh, "tw", "/tmp/r.gz")).to be_a(Integer)
    end
  end

  describe "raw Net::SSH streaming channels" do
    let(:job) { described_class.new }

    # Fake Net::SSH session/channel: captures the wire + the bytes sent, drives
    # the exec/on_extended_data callbacks the way a real channel would.
    def fake_ssh_channel(sent:, execed:, success: true)
      ch = double("ch")
      allow(ch).to receive(:exec) { |wire, &blk| execed << wire; blk.call(ch, success) }
      allow(ch).to receive(:send_data) { |d| sent << d }
      allow(ch).to receive(:eof!)
      allow(ch).to receive(:on_extended_data) { |&blk| blk.call(nil, nil, "stderr noise\n") }
      outer = double("channel", wait: nil)
      session = double("session")
      allow(session).to receive(:open_channel) { |&blk| blk.call(ch); outer }
      allow(Net::SSH).to receive(:start).and_yield(session)
    end

    describe "#stream_gunzip" do
      it "gunzips locally and streams the plain bytes into the wire's stdin, passing the server key" do
        server = create(:server, ssh_private_key: "PRIVKEY")
        gz = Tempfile.create([ "s", ".gz" ])
        Zlib::GzipWriter.open(gz.path) { |w| w.write("hello dump") }
        sent = +""; execed = []
        fake_ssh_channel(sent: sent, execed: execed)
        allow(Rails.logger).to receive(:warn)

        job.send(:stream_gunzip, server, "wire-cmd", gz.path)

        expect(execed).to eq([ "wire-cmd" ])
        expect(sent).to eq("hello dump")
        expect(Net::SSH).to have_received(:start)
          .with(server.host, "root", hash_including(port: 22, key_data: [ "PRIVKEY" ]))
        expect(Rails.logger).to have_received(:warn).with(/import stderr: stderr noise/)
      ensure
        File.unlink(gz.path) if gz && File.exist?(gz.path)
      end

      it "raises when the remote exec fails to start" do
        server = create(:server)
        gz = Tempfile.create([ "s", ".gz" ])
        Zlib::GzipWriter.open(gz.path) { |w| w.write("x") }
        fake_ssh_channel(sent: +"", execed: [], success: false)

        expect { job.send(:stream_gunzip, server, "wire-cmd", gz.path) }
          .to raise_error(/Failed to execute wire-cmd/)
      ensure
        File.unlink(gz.path) if gz && File.exist?(gz.path)
      end
    end

    it "stream_gunzip and upload_and_untar connect as the configured host SSH user" do
      allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
      server = create(:server)
      gz = Tempfile.create([ "s", ".gz" ])
      Zlib::GzipWriter.open(gz.path) { |w| w.write("x") }
      fake_ssh_channel(sent: +"", execed: [])
      allow(Rails.logger).to receive(:warn)

      job.send(:stream_gunzip, server, "wire-cmd", gz.path)
      job.send(:upload_and_untar, server, gz.path, "/tmp/dr-volume-abc")

      expect(Net::SSH).to have_received(:start).with(server.host, "wokku", anything).twice
    ensure
      File.unlink(gz.path) if gz && File.exist?(gz.path)
    end

    describe "#upload_and_untar" do
      it "streams the raw tarball bytes into a root tar -xzf into the throwaway dir" do
        server = create(:server) # no ssh_private_key -> no key_data
        tar = Tempfile.create([ "t", ".tar.gz" ])
        File.binwrite(tar.path, "TARBYTES")
        sent = +""; execed = []
        fake_ssh_channel(sent: sent, execed: execed)
        allow(Rails.logger).to receive(:warn)

        job.send(:upload_and_untar, server, tar.path, "/tmp/dr-volume-abc")

        expect(execed).to eq([ "mkdir -p /tmp/dr-volume-abc && tar -xzf - -C /tmp/dr-volume-abc" ])
        expect(sent).to eq("TARBYTES")
        expect(Net::SSH).to have_received(:start)
          .with(server.host, "root", hash_not_including(:key_data))
        expect(Rails.logger).to have_received(:warn).with(/untar stderr: stderr noise/)
      ensure
        File.unlink(tar.path) if tar && File.exist?(tar.path)
      end
    end
  end

  describe "#counts and #dsn_password" do
    let(:job) { described_class.new }

    it "regexes TBL=/MARK= out of noisy client output" do
      ssh = instance_double(Hosts::Ssh)
      allow(ssh).to receive(:run_raw).and_return("banner\nTBL=7\n", "warning: blah\nMARK=4200\n")

      expect(job.send(:counts, ssh, "postgres", "c", db: "d", password: nil)).to eq([ 7, 4200 ])
    end

    it "count_exec raises on an unknown engine" do
      expect { job.send(:count_exec, "sqlite", "c", "d", nil, "q") }
        .to raise_error(ArgumentError, /no count client for sqlite/)
    end

    it "dsn_password extracts the password from the dsn, nil when there is no dsn" do
      with = build(:database_service, dsn: "postgres://wokku:s3cret@10.0.0.9:5432/mydb")
      expect(job.send(:dsn_password, with)).to eq("s3cret")

      without = build(:database_service, dsn: nil)
      expect(job.send(:dsn_password, without)).to be_nil
    end

    it "live_password: never a tenant's own dsn password" do
      expect(job.send(:live_password, build(:database_service, service_type: "mariadb", shared: true, dsn: "mysql://t:pw@h/d"))).to eq(:container_env)
      expect(job.send(:live_password, build(:database_service, service_type: "postgres", shared: true, dsn: "postgres://t:pw@h/d"))).to be_nil
      expect(job.send(:live_password, build(:database_service, service_type: "postgres", dsn: "postgres://u:pw@h/d"))).to eq("pw")
    end
  end

  describe "#run_volume_drill (stubbed transports)" do
    let(:job) { described_class.new }
    let(:app) { create(:app_record) }
    let(:backup) do
      create(:backup, :volume, app_record: app,
             mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
    end

    def stub_volume_transports(find: "118", du: "51800000")
      ssh = instance_double(Hosts::Ssh)
      allow(Hosts::Ssh).to receive(:new).with(app.server).and_return(ssh)
      allow(ssh).to receive(:run_raw) do |cmd, **|
        cmd.start_with?("find ") ? find : du
      end
      dest = backup.backup_destination
      s3 = double("s3")
      allow(dest).to receive(:s3_client).and_return(s3)
      allow(s3).to receive(:get_object) do |bucket:, key:, response_target:|
        File.binwrite(response_target, "tar-gz-bytes")
      end
      allow(job).to receive(:upload_and_untar)
      ssh
    end

    it "downloads + decrypts + untars, counts restored and live, and unlinks the decrypted temp" do
      stub_volume_transports
      dec = Tempfile.create("dec-tar"); dec.write("plain-tar"); dec.close
      allow(job).to receive(:decrypt_backup).and_return(dec.path)

      r = job.send(:run_volume_drill, backup, "/tmp/dr-volume-abc")

      expect(job).to have_received(:upload_and_untar).with(app.server, dec.path, "/tmp/dr-volume-abc")
      expect(r[:restored_tables]).to eq(118)
      expect(r[:live_tables]).to eq(118)
      expect(r[:restored_rows]).to eq(51_800_000)
      expect(r[:live_rows]).to eq(51_800_000)
      expect(r[:rto_ms]).to be_a(Integer)
      expect(File.exist?(dec.path)).to be(false)
    end

    it "skips the live count (0/0) when the live mount fails the STORAGE_ROOT anchor" do
      stub_volume_transports
      allow(job).to receive(:decrypt_backup) { |_b, path| path }
      allow(VolumeBackupService).to receive(:safe_mount?).and_return(false)
      expect(Rails.logger).to receive(:warn).with(/failed anchor; comparing on restored counts only/)

      r = job.send(:run_volume_drill, backup, "/tmp/dr-volume-abc")

      expect(r[:live_tables]).to eq(0)
      expect(r[:live_rows]).to eq(0)
      expect(r[:restored_tables]).to eq(118)
    end
  end

  it "destroy_volume_throwaway logs the orphan loudly instead of raising when rm fails" do
    app = create(:app_record)
    backup = create(:backup, :volume, app_record: app,
                    mount_path: "/var/lib/dokku/data/storage/#{app.name}/uploads", status: "completed")
    ssh = instance_double(Hosts::Ssh)
    allow(Hosts::Ssh).to receive(:new).and_return(ssh)
    allow(ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError, "rm denied")
    expect(Rails.logger).to receive(:error).with(%r{ORPHAN volume throwaway /tmp/dr-volume-abc123})

    expect { described_class.new.send(:destroy_volume_throwaway, "/tmp/dr-volume-abc123", backup) }
      .not_to raise_error
  end
end
