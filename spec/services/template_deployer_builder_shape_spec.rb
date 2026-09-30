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

    it "refuses a shape the plan enforcer rejects" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(false)
      result = described_class.new(template: template, app_name: "shaped", server: server, user: user).deploy!
      expect(result[:error]).to match(/over your account limit/)
      expect(DynoAllocation.joins(:app_record).where(app_records: { name: "shaped" })).to be_empty
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
