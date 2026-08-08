# frozen_string_literal: true

require "rails_helper"

RSpec.describe SharedDatabaseQuotaJob, type: :job do
  let(:server) { servers(:two) }

  # Shared tenants require a parent (host) DatabaseService record.
  let(:parent) do
    DatabaseService.create!(
      name: "wokku-shared-free", service_type: "postgres",
      server: server, shared: false, wokkud_managed: true
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

  it "skips servers with no shared postgres tenants" do
    expect(Services::Ops).not_to receive(:issue_and_wait!)
    described_class.new.perform
  end

  it "sweeps via a typed check_quotas op and mirrors over_quota_at" do
    tenant = make_tenant(name: "bigsite", shared_db_name: "bigsite_db")
    op = build_stubbed(:service_op, status: :succeeded,
      result: { "tenants" => [
        { "slug" => tenant.shared_db_name, "size_bytes" => 999, "cap_bytes" => 100, "over" => true, "read_only" => true }
      ] })
    expect(Services::Ops).to receive(:issue_and_wait!)
      .with(service: parent, kind: "service.check_quotas",
            params: { tenants: [ { slug: tenant.shared_db_name, cap_bytes: tenant.storage_mb_quota.to_i * 1.megabyte } ] })
      .and_return(op)
    expect(Hosts::Ssh).not_to receive(:new)

    described_class.new.perform

    expect(tenant.reload.over_quota_at).to be_present
  end

  it "clears over_quota_at when the op reports the tenant back under quota" do
    tenant = make_tenant(name: "recovered", shared_db_name: "recovered_db", over_quota_at: 1.day.ago)
    op = build_stubbed(:service_op, status: :succeeded,
      result: { "tenants" => [
        { "slug" => tenant.shared_db_name, "size_bytes" => 10, "cap_bytes" => 150 * 1.megabyte, "over" => false, "read_only" => false }
      ] })
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(op)

    described_class.new.perform

    expect(tenant.reload.over_quota_at).to be_nil
  end

  it "ignores op reports for tenants we don't track in Rails (defensive)" do
    tenant = make_tenant(name: "known", shared_db_name: "known_db")
    op = build_stubbed(:service_op, status: :succeeded,
      result: { "tenants" => [
        { "slug" => tenant.shared_db_name, "size_bytes" => 10, "cap_bytes" => 100, "over" => false, "read_only" => false },
        { "slug" => "stranger_db", "size_bytes" => 999, "cap_bytes" => 100, "over" => true, "read_only" => true }
      ] })
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(op)

    expect { described_class.new.perform }.not_to raise_error
  end

  it "logs and continues if the op fails (one bad server doesn't kill the sweep)" do
    make_tenant(name: "boom", shared_db_name: "boom_db")
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(build_stubbed(:service_op, status: :failed, error: "quota_check_failed")))

    expect(Rails.logger).to receive(:warn).with(/SharedDatabaseQuotaJob/)

    expect { described_class.new.perform }.not_to raise_error
  end
end
