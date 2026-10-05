require "rails_helper"

RSpec.describe DatastoreReconcileJob, type: :job do
  let(:server) { create(:server, wokkud_services_enabled: true) }

  def managed(attrs) = create(:database_service, { server: server, wokkud_managed: true }.merge(attrs))

  it "issues service.ensure for a dedicated managed service" do
    db = managed(service_type: "postgres", tier_name: "basic", name: "app-db")
    expect(Services::Ops).to receive(:issue_and_wait!)
      .with(hash_including(service: db, kind: "service.ensure"))
      .and_return(instance_double("ServiceOp", succeeded?: true))
    described_class.perform_now
  end

  it "skips shared tenants (no own container)" do
    parent = managed(service_type: "postgres", tier_name: "shared_host", name: "dokku-shared-postgres")
    tenant = managed(service_type: "postgres", tier_name: "shared_free", name: "app-pg-shared-abc",
                     shared: true, parent_service: parent)
    seen = []
    allow(Services::Ops).to receive(:issue_and_wait!) { |a| seen << a[:service]; instance_double("ServiceOp", succeeded?: true) }
    described_class.perform_now
    expect(seen).to include(parent)
    expect(seen).not_to include(tenant)
  end

  it "ensures the shared mariadb parent with empty params (wokkud owns its run-spec)" do
    parent = managed(service_type: "mariadb", tier_name: "shared_host", name: "dokku-shared-mariadb")
    expect(Services::Ops).to receive(:issue_and_wait!)
      .with(service: parent, kind: "service.ensure", params: {}, timeout: described_class::ENSURE_TIMEOUT)
      .and_return(instance_double("ServiceOp", succeeded?: true))
    described_class.perform_now
  end

  it "excludes other shared parents (shared_host that are not dokku-shared-postgres)" do
    memcached_parent = managed(service_type: "memcached", tier_name: "shared_host", name: "dokku-shared-memcached")
    seen = []
    allow(Services::Ops).to receive(:issue_and_wait!) { |a| seen << a[:service]; instance_double("ServiceOp", succeeded?: true) }
    described_class.perform_now
    expect(seen).not_to include(memcached_parent)
  end

  # DatabaseService has no :crashed enum (that is AppRecord's); its failure
  # state is :error. Data-missing = unrecoverable-without-restore -> :error.
  it "reconciles a stale running->error when ensure fails data_dir_missing" do
    db = managed(service_type: "postgres", tier_name: "basic", name: "gone-db", status: :running)
    failed = Services::Ops::Failed.new(instance_double("ServiceOp", error_code: "data_dir_missing", kind: "service.ensure", error: "x"))
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(failed)
    described_class.perform_now
    expect(db.reload.status).to eq("error")
  end

  it "does NOT flip status on a transient (non-data-missing) failure" do
    db = managed(service_type: "postgres", tier_name: "basic", name: "flaky-db", status: :running)
    failed = Services::Ops::Failed.new(instance_double("ServiceOp", error_code: "service_ensure_failed", kind: "service.ensure", error: "docker down"))
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(failed)
    described_class.perform_now
    expect(db.reload.status).to eq("running")
  end

  it "reconciles a stale non-running->running on success" do
    db = managed(service_type: "postgres", tier_name: "basic", name: "back-db", status: :error)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(instance_double("ServiceOp", succeeded?: true))
    described_class.perform_now
    expect(db.reload.status).to eq("running")
  end

  # Credential boundary (databasement): ensure recreates a dedicated service
  # from its intact data dir only — admin_pass must always be issued empty,
  # never a real password, so this supervision loop never reads/stores/logs
  # a credential.
  it "issues an empty admin_pass for a dedicated service (credential boundary)" do
    db = managed(service_type: "postgres", tier_name: "basic", name: "app-db")
    captured_params = nil
    allow(Services::Ops).to receive(:issue_and_wait!) do |**kwargs|
      captured_params = kwargs[:params]
      instance_double("ServiceOp", succeeded?: true)
    end
    described_class.perform_now
    expect(captured_params[:admin_pass]).to eq("")
  end

  # Operator-visible heal trail: a recreate (container gone, rebuilt on
  # intact data — the shared-parent incident) must leave a log line +
  # Sentry breadcrumb, or a crash-loop is invisible.
  it "logs and breadcrumbs a recreate when service.ensure reports action=recreated" do
    managed(service_type: "postgres", tier_name: "basic", name: "recreated-db")
    allow(Services::Ops).to receive(:issue_and_wait!)
      .and_return(instance_double("ServiceOp", succeeded?: true, result: { "action" => "recreated" }))
    expect(Rails.logger).to receive(:warn).with(/recreated recreated-db/)
    expect(Sentry).to receive(:capture_message).with(/recreated-db/, level: :info)
    described_class.perform_now
  end

  it "does NOT log a recreate when service.ensure reports action=none" do
    managed(service_type: "postgres", tier_name: "basic", name: "steady-db")
    allow(Services::Ops).to receive(:issue_and_wait!)
      .and_return(instance_double("ServiceOp", succeeded?: true, result: { "action" => "none" }))
    expect(Rails.logger).not_to receive(:warn)
    expect(Sentry).not_to receive(:capture_message)
    described_class.perform_now
  end

  it "one failing service does not abort the sweep" do
    bad = managed(service_type: "postgres", tier_name: "basic", name: "bad-db")
    good = managed(service_type: "postgres", tier_name: "basic", name: "good-db")
    allow(Services::Ops).to receive(:issue_and_wait!) do |a|
      raise Services::Ops::Timeout, "t" if a[:service] == bad
      instance_double("ServiceOp", succeeded?: true)
    end
    expect { described_class.perform_now }.not_to raise_error
    expect(Services::Ops).to have_received(:issue_and_wait!).with(hash_including(service: good))
  end
end
