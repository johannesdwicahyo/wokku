require "rails_helper"

RSpec.describe VolumeBackupService do
  def with_env(vars)
    saved = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(saved)
  end

  let(:key) { Base64.strict_encode64("k" * 32) }

  describe ".mount_host_paths" do
    let(:app) { create(:app_record) }
    let(:ssh) { instance_double(Hosts::Ssh) }
    let(:container) { "wokku-#{app.name}-web.1.abc123" }

    before { allow(Hosts::Ssh).to receive(:new).with(app.server).and_return(ssh) }

    it "inspects the live web task's mounts and skips paths outside the storage root" do
      allow(ssh).to receive(:run_raw).with("docker ps --format '{{.Names}}'", timeout: 30)
        .and_return("wokku-other-web.1.zzz\n#{container}\n")
      allow(ssh).to receive(:run_raw)
        .with("docker inspect -f #{Shellwords.escape(described_class::MOUNTS_FORMAT)} #{container}", timeout: 30)
        .and_return([
          "/var/lib/dokku/data/storage/#{app.name}/uploads:/app/uploads",
          "/etc:/host-etc",                                       # misconfigured — skip
          "/var/lib/dokku/data/storage/#{app.name}/../../../etc:/x", # traversal — skip
          ""                                                      # trailing blank — skip
        ].join("\n"))
      expect(described_class.mount_host_paths(app))
        .to eq([ "/var/lib/dokku/data/storage/#{app.name}/uploads" ])
    end

    it "returns [] with a warning when the app has no running web task" do
      allow(ssh).to receive(:run_raw).with("docker ps --format '{{.Names}}'", timeout: 30)
        .and_return("wokku-other-web.1.zzz\n")
      expect(Rails.logger).to receive(:warn).with(/no running web task/)
      expect(described_class.mount_host_paths(app)).to eq([])
    end
  end

  describe "#perform!" do
    it "streams tar as root (stderr excluded), encrypts, uploads, records a completed volume Backup" do
      with_env("BACKUP_ENCRYPTION_KEY" => key) do
        app = create(:app_record)
        dest = create(:backup_destination, server: app.server)
        allow(app.server).to receive(:backup_destination).and_return(dest)
        mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"

        streamed = nil
        allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming) do |_c, cmd, **kw, &blk|
          streamed = { cmd: cmd, kwargs: kw }
          blk.call("FAKE-TAR-GZ-BYTES")
        end
        uploaded = nil
        s3 = dest.s3_client
        allow(dest).to receive(:s3_client).and_return(s3)
        allow(s3).to receive(:put_object) { |args| uploaded = { key: args[:key], body: args[:body].read } }

        backup = described_class.new(app, mount).perform!

        expect(streamed[:cmd]).to include("tar -czf -")
        expect(streamed[:cmd]).to include(Shellwords.escape(mount))
        expect(streamed[:kwargs]).to eq(include_stderr: false, timeout: VolumeBackupService::TAR_TIMEOUT)
        expect(backup).to be_kind_volume
        expect(backup.status).to eq("completed")
        expect(backup.encrypted?).to be(true)
        expect(backup.mount_path).to eq(mount)
        expect(backup.app_record).to eq(app)
        expect(backup.database_service).to be_nil
        expect(uploaded[:key]).to match(%r{volume/#{app.name}/uploads-[0-9a-f]{8}/.+\.tar\.gz\.enc\z})
        expect(uploaded[:body]).not_to include("FAKE-TAR-GZ-BYTES")   # encrypted
        # round-trip: decrypt the uploaded blob back to the tar bytes
        t = Tempfile.new(binmode: true); t.write(uploaded[:body]); t.flush
        dec = BackupCipher.decrypt_file(t.path)
        expect(File.binread(dec)).to eq("FAKE-TAR-GZ-BYTES")
        File.unlink(dec)
      end
    end

    it "escapes shell metacharacters in mount paths before invoking tar as root" do
      with_env("BACKUP_ENCRYPTION_KEY" => key) do
        app = create(:app_record)
        dest = create(:backup_destination, server: app.server)
        allow(app.server).to receive(:backup_destination).and_return(dest)
        # Hostile mount path: spaces + command injection attempt.
        # Safe under safe_mount? (anchored, no `..`, no control chars) but
        # MUST be escaped before reaching the root shell.
        mount = "/var/lib/dokku/data/storage/#{app.name}/a b$(reboot)"

        streamed = nil
        allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming) do |_c, cmd, **kw, &blk|
          streamed = { cmd: cmd, kwargs: kw }
          blk.call("FAKE-TAR-GZ-BYTES")
        end
        s3 = dest.s3_client
        allow(dest).to receive(:s3_client).and_return(s3)
        allow(s3).to receive(:put_object) { |args| { key: args[:key], body: args[:body].read } }

        backup = described_class.new(app, mount).perform!

        # Tripwire: the command MUST include the Shellwords-escaped mount.
        expect(streamed[:cmd]).to include(Shellwords.escape(mount))
        # Tripwire: the command MUST NOT include the raw $(reboot) unescaped.
        # Regex: (?<!\\) = negative lookbehind for backslash (unescaped $).
        expect(streamed[:cmd]).not_to match(/(?<!\\)\$\(reboot\)/)
        # Command format is `tar -czf - -C <escaped_mount> .`
        expect(streamed[:cmd]).to match(/tar -czf - -C #{Regexp.escape(Shellwords.escape(mount))} \./)
        expect(backup.mount_path).to eq(mount)
        expect(backup.status).to eq("completed")
      end
    end

    it "as a non-root host user, tars through the sudo helper" do
      allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
      app = create(:app_record)
      dest = create(:backup_destination, server: app.server)
      allow(app.server).to receive(:backup_destination).and_return(dest)
      mount = "/var/lib/dokku/data/storage/#{app.name}/a b"
      streamed = nil
      allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming) do |_c, cmd, **_kw, &blk|
        streamed = cmd
        blk.call("FAKE")
      end
      s3 = dest.s3_client
      allow(dest).to receive(:s3_client).and_return(s3)
      allow(s3).to receive(:put_object)

      with_env("BACKUP_ENCRYPTION_KEY" => key) { described_class.new(app, mount).perform! }

      expect(streamed).to eq("sudo -n /usr/local/sbin/wokku-volume-tar #{Shellwords.escape(mount)}")
    end

    it "refuses a mount path outside the storage root before touching a root shell" do
      app = create(:app_record)
      expect { described_class.new(app, "/etc").perform! }
        .to raise_error(VolumeBackupService::UnsafeMountPath)
      expect(Backup.kind_volume.count).to eq(0)
    end

    it "refuses a traversal path even under the storage root" do
      app = create(:app_record)
      expect { described_class.new(app, "/var/lib/dokku/data/storage/#{app.name}/../../etc").perform! }
        .to raise_error(VolumeBackupService::UnsafeMountPath)
    end

    it "marks the backup failed and re-raises when the tar stream errors" do
      with_env("BACKUP_ENCRYPTION_KEY" => key) do
        app = create(:app_record)
        dest = create(:backup_destination, server: app.server)
        allow(app.server).to receive(:backup_destination).and_return(dest)
        mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"
        allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming)
          .and_raise(Hosts::Ssh::CommandError.new("tar failed", exit_code: 2, stderr: "boom"))

        expect { described_class.new(app, mount).perform! }.to raise_error(Hosts::Ssh::CommandError)
        expect(Backup.kind_volume.last.status).to eq("failed")
      end
    end
  end
end
