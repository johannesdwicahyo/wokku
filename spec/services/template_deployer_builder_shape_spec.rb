# frozen_string_literal: true

require "rails_helper"

# Per-resource billing launch blocker B: with the builder on, a tier-only row
# bills Rp0 forever — template deploys must be born shaped.
RSpec.describe TemplateDeployer, "builder-mode shapes" do
  let(:server) { servers(:one) }
  let(:user) { users(:one) }
  let(:template) { { repo: "https://github.com/x/y", min_tier: "basic", addons: [ { "type" => "postgres" } ] } }

  before do
    server.update!(wokkud_services_enabled: true)
    ServiceTier.create!(service_type: "postgres", name: "basic", spec: { "memory_mb" => 512, "storage_gb" => 5 })
    allow(Wokku.config.dns_provider).to receive(:create_app_record).and_return(nil)
    allow(Wokku.config.dns_provider).to receive(:delete_app_record).and_return(nil)
    allow(::Lifecycle::Ops).to receive(:remove!).and_return(true)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(true)
    allow(GithubDeployJob).to receive(:system_fetch).and_return(nil)
    allow_any_instance_of(Git::BareRepo).to receive(:ensure!).and_return(nil)
    allow_any_instance_of(described_class).to receive(:resolve_sha).and_return("a" * 40)
    allow_any_instance_of(Git::PushDeployer).to receive(:call).and_return(nil)
  end

  def deploy(tpl = template, name: "shaped")
    described_class.new(template: tpl, app_name: name, server: server, user: user).deploy!
    AppRecord.find_by!(name: name, server: server)
  end

  context "builder on" do
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(true) }

    it "creates a shaped web allocation and a shaped dedicated DB" do
      app = deploy
      web = app.dyno_allocations.find_by!(process_type: "web")
      # basic (0.3 vCPU / 512 MB) rounded up onto the grid, like ShapeBackfill.
      expect([ web.dyno_tier_id, web.cpu.to_f, web.memory_mb ]).to eq([ nil, 0.5, 512 ])
      expect(web).not_to be_sleeping

      db = app.database_services.sole
      expect(db.shape.to_h).to eq(cpu: 0.25, memory_mb: 512, disk_gb: 5)
    end

    it "keeps a free template sleeping (tier, no shape)" do
      web = deploy({ repo: "https://github.com/x/y" }, name: "sleepy").dyno_allocations.sole
      expect(web.shape).to be_nil
      expect(web).to be_sleeping
    end

    it "refuses over the account limit before creating anything" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(false)
      expect(DatabaseProvisioner).not_to receive(:new)
      result = nil
      expect {
        result = described_class.new(template: template, app_name: "shaped", server: server, user: user).deploy!
      }.to not_change(AppRecord, :count).and not_change(DynoAllocation, :count).and not_change(DatabaseService, :count)
      expect(result[:error]).to match(/over your account limit/)
    end

    # Review #4: a job-time refusal (the controller already created the app)
    # fails cleanly — no host rollback op, app not marked crashed.
    it "a job-time refusal leaves the controller-created app never-deployed, with no host op" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(false)
      app = AppRecord.create!(name: "queued", server: server, team: user.teams.first, creator: user,
                              deploy_branch: "main", status: :deploying)
      expect(::Lifecycle::Ops).not_to receive(:remove!)
      result = described_class.new(template: template, app_name: "queued", server: server, user: user).deploy!
      expect(result).to include(success: false, error: match(/over your account limit/))
      expect(app.reload.status).to eq("created")
      expect(app.dyno_allocations).to be_empty
    end

    it "checks the web process and its datastores as one change" do
      expect(Resources::ApplyChange).to receive(:check_new_shape)
        .with(hash_including(app_shapes: [ Resources::Shape.new(cpu: 0.5, memory_mb: 512) ], shapes: [ Resources::Shape.new(cpu: 0.25, memory_mb: 512, disk_gb: 5) ]))
        .and_return(Resources::ApplyChange::Result.new(ok: true))
      deploy
    end

    it "#builder_preflight is ok for a free template with no datastores" do
      deployer = described_class.new(template: { repo: "x" }, app_name: "p", server: server, user: user)
      expect(deployer.builder_preflight(AppRecord.new(team: user.teams.first)).ok).to be true
    end
  end

  context "builder off" do
    before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

    it "keeps tier-only rows" do
      app = deploy
      web = app.dyno_allocations.sole
      expect([ web.dyno_tier.name, web.cpu ]).to eq([ "basic", nil ])
      db = app.database_services.sole
      expect([ db.tier_name, db.cpu ]).to eq([ "basic", nil ])
    end
  end
end
