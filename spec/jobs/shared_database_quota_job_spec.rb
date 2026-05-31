# frozen_string_literal: true

require "rails_helper"

RSpec.describe SharedDatabaseQuotaJob, type: :job do
  let(:server) { servers(:two) }
  let(:client) { instance_double(Dokku::Client) }
  let(:shared) { instance_double(Dokku::SharedPostgres) }

  # Shared tenants require a parent (host) DatabaseService record.
  let(:parent) do
    DatabaseService.create!(
      name: "wokku-shared-free", service_type: "postgres",
      server: server, shared: false
    )
  end

  def make_tenant(name:, server: self.server, **attrs)
    DatabaseService.create!(
      name: name, service_type: "postgres", shared: true,
      server: server, storage_mb_quota: 150,
      parent_service: parent,
      **attrs
    )
  end

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    allow(Dokku::SharedPostgres).to receive(:new).with(client).and_return(shared)
  end

  it "skips servers with no shared tenants" do
    expect(shared).not_to receive(:check_quotas!)
    described_class.new.perform
  end

  it "marks over_quota_at when the plugin reports a tenant over quota" do
    tenant = make_tenant(name: "bigsite")
    allow(shared).to receive(:check_quotas!).and_return([
      { name: "bigsite", size_mb: 175, quota_mb: 150, over_quota: true, revoked: true }
    ])

    described_class.new.perform

    expect(tenant.reload.over_quota_at).to be_present
  end

  it "clears over_quota_at when a previously-over tenant comes back under" do
    tenant = make_tenant(name: "recovered", over_quota_at: 1.day.ago)
    allow(shared).to receive(:check_quotas!).and_return([
      { name: "recovered", size_mb: 80, quota_mb: 150, over_quota: false, revoked: false }
    ])

    described_class.new.perform

    expect(tenant.reload.over_quota_at).to be_nil
  end

  it "ignores plugin reports for tenants we don't track in Rails (defensive)" do
    make_tenant(name: "known")
    allow(shared).to receive(:check_quotas!).and_return([
      { name: "known",    size_mb: 10,  quota_mb: 150, over_quota: false, revoked: false },
      { name: "stranger", size_mb: 999, quota_mb: 150, over_quota: true,  revoked: true }
    ])

    expect { described_class.new.perform }.not_to raise_error
  end

  it "logs and continues if check_quotas! raises (one bad server doesn't kill the sweep)" do
    other_server = servers(:one)
    other_client = instance_double(Dokku::Client)
    other_shared = instance_double(Dokku::SharedPostgres)
    allow(Dokku::Client).to receive(:new).with(other_server).and_return(other_client)
    allow(Dokku::SharedPostgres).to receive(:new).with(other_client).and_return(other_shared)

    other_parent = DatabaseService.create!(
      name: "wokku-shared-free", service_type: "postgres",
      server: other_server, shared: false
    )
    DatabaseService.create!(
      name: "ok", service_type: "postgres", shared: true,
      server: other_server, storage_mb_quota: 150, parent_service: other_parent
    )
    make_tenant(name: "boom")

    allow(shared).to receive(:check_quotas!).and_raise(Dokku::Client::ConnectionError, "unreachable")
    expect(other_shared).to receive(:check_quotas!).and_return([])

    expect(Rails.logger).to receive(:warn).with(/SharedDatabaseQuotaJob/).at_least(:once)

    expect { described_class.new.perform }.not_to raise_error
  end
end
