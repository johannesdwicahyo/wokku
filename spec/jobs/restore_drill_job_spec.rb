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
end
