require "rails_helper"

RSpec.describe VolumeBackupJob do
  it "backs up each anchored mount and isolates per-mount failures" do
    app = create(:app_record)
    m1 = "/var/lib/dokku/data/storage/#{app.name}/uploads"
    m2 = "/var/lib/dokku/data/storage/#{app.name}/cache"
    allow(VolumeBackupService).to receive(:mount_host_paths).with(app).and_return([ m1, m2 ])

    good = instance_double(VolumeBackupService, perform!: true)
    allow(VolumeBackupService).to receive(:new).with(app, m1).and_raise("tar blew up")
    allow(VolumeBackupService).to receive(:new).with(app, m2).and_return(good)
    expect(Sentry).to receive(:capture_exception)

    described_class.new.perform(app.id)
    expect(good).to have_received(:perform!)
  end

  it "no-ops for an app with no mounts" do
    app = create(:app_record)
    allow(VolumeBackupService).to receive(:mount_host_paths).with(app).and_return([])
    expect(VolumeBackupService).not_to receive(:new)
    described_class.new.perform(app.id)
  end

  it "logs at warn and skips Sentry when the mount dir vanished (removed mount, not an incident)" do
    app = create(:app_record)
    mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"
    allow(VolumeBackupService).to receive(:mount_host_paths).with(app).and_return([ mount ])
    error = Hosts::Ssh::CommandError.new("tar failed", exit_code: 1,
      stderr: "tar: /var/lib/dokku/data/storage/#{app.name}/uploads: No such file or directory")
    allow(VolumeBackupService).to receive(:new).with(app, mount).and_raise(error)
    expect(Sentry).not_to receive(:capture_exception)
    expect(Rails.logger).to receive(:warn).with(/mount vanished/)

    described_class.new.perform(app.id)
  end

  it "still reports to Sentry for any other tar failure" do
    app = create(:app_record)
    mount = "/var/lib/dokku/data/storage/#{app.name}/uploads"
    allow(VolumeBackupService).to receive(:mount_host_paths).with(app).and_return([ mount ])
    error = Hosts::Ssh::CommandError.new("tar failed", exit_code: 1, stderr: "tar: permission denied")
    allow(VolumeBackupService).to receive(:new).with(app, mount).and_raise(error)
    expect(Sentry).to receive(:capture_exception)

    described_class.new.perform(app.id)
  end
end
