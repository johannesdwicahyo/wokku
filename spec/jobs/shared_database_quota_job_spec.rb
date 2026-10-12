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
    expect(tenant.live_db_bytes).to eq(999) # the sweep is shared tenants' only size source
    expect(tenant.live_metrics_at).to be_present
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

  describe "shared mariadb tenants" do
    let(:maria_parent) do
      DatabaseService.create!(
        name: "dokku-shared-mariadb", service_type: "mariadb", tier_name: "shared_host",
        server: server, shared: false, wokkud_managed: true
      )
    end

    def maria_tenant(name:, **attrs)
      DatabaseService.create!(
        name: name, service_type: "mariadb", shared: true, tier_name: "shared_free",
        server: server, storage_mb_quota: 1024, parent_service: maria_parent, **attrs
      )
    end

    def op_reporting(*statuses)
      build_stubbed(:service_op, status: :succeeded, result: { "tenants" => statuses })
    end

    it "sweeps them with their OWN check_quotas op on the mariadb parent (cap = storage_mb_quota)" do
      tenant = maria_tenant(name: "shop-mariadb-shared-abc", shared_db_name: "shop")
      expect(Services::Ops).to receive(:issue_and_wait!)
        .with(service: maria_parent, kind: "service.check_quotas",
              params: { tenants: [ { slug: "shop", cap_bytes: 1024 * 1.megabyte } ] })
        .and_return(op_reporting({ "slug" => "shop", "size_bytes" => 2.gigabytes, "over" => true }))

      described_class.new.perform

      expect(tenant.reload.over_quota_at).to be_present
    end

    it "fires the team event once when a tenant goes over, and keeps the original timestamp (24h grace clock)" do
      tenant = maria_tenant(name: "over-mariadb-shared-abc", shared_db_name: "over")
      allow(Services::Ops).to receive(:issue_and_wait!)
        .and_return(op_reporting({ "slug" => "over", "size_bytes" => 2.gigabytes, "over" => true }))
      job = described_class.new
      allow(job).to receive(:fire_team_event)

      job.perform
      first = tenant.reload.over_quota_at
      travel 1.hour do
        job.perform
      end

      expect(job).to have_received(:fire_team_event).with(anything, "shared_db_over_quota", hash_including(db: tenant.name)).once
      expect(tenant.reload.over_quota_at).to eq(first)
    end

    it "clears over_quota_at when back under" do
      tenant = maria_tenant(name: "ok-mariadb-shared-abc", shared_db_name: "ok", over_quota_at: 2.hours.ago)
      allow(Services::Ops).to receive(:issue_and_wait!)
        .and_return(op_reporting({ "slug" => "ok", "size_bytes" => 10, "over" => false }))

      described_class.new.perform

      expect(tenant.reload.over_quota_at).to be_nil
    end

    it "leaves a tenant untouched when wokkud reports an error for it, and still applies the rest" do
      broken = maria_tenant(name: "broken-mariadb-shared-abc", shared_db_name: "broken", over_quota_at: 2.hours.ago)
      fine   = maria_tenant(name: "fine-mariadb-shared-abc", shared_db_name: "fine")
      allow(Services::Ops).to receive(:issue_and_wait!).and_return(op_reporting(
        { "slug" => "broken", "error" => "quota flip: no such grant" },
        { "slug" => "fine", "size_bytes" => 2.gigabytes, "over" => true }
      ))

      described_class.new.perform

      expect(broken.reload.over_quota_at).to be_present # not cleared by a failed check
      expect(broken.live_db_bytes).to be_nil            # nor sized from a meaningless field
      expect(fine.reload.over_quota_at).to be_present
    end

    it "sweeps postgres and mariadb parents on the same server separately" do
      make_tenant(name: "pg1", shared_db_name: "pg1")
      maria_tenant(name: "m1-mariadb-shared-abc", shared_db_name: "m1")
      seen = []
      allow(Services::Ops).to receive(:issue_and_wait!) { |service:, **| seen << service; op_reporting }

      described_class.new.perform

      expect(seen).to contain_exactly(parent, maria_parent)
    end
  end
end
