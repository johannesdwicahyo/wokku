require "rails_helper"

# P1 final whole-branch review fixes (C1, I3, I5, I7, M2) — request level.
RSpec.describe "Per-resource sizing gates", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:headers)    { api_v1_headers(user) }

  def builder_off! = allow(Wokku.config).to receive(:resource_builder?).and_return(false)

  def refuse_resources!
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_call_original
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).with(anything, :resources, hash_including(:from, :to)).and_return(false)
  end

  describe "C1: flag off refuses every sizing endpoint" do
    before { builder_off! }

    it "API ps#update with resources → 422, nothing persisted" do
      patch "/api/v1/apps/#{app_record.id}/ps", params: { resources: { web: { cpu: "0.5", memory_mb: "1024" } } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Custom sizing is not enabled")
      expect(app_record.dyno_allocations.where.not(cpu: nil)).to be_empty
    end

    it "dashboard resources#update → alert, nothing persisted" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/resources", params: { processes: { web: { cpu: "0.5", memory_mb: "1024", count: "1" } }, volume_disk_gb: "5" }
      expect(flash[:alert]).to eq("Custom sizing is not enabled on this server.")
      expect(app_record.dyno_allocations.where.not(cpu: nil)).to be_empty
      expect(app_record.reload.volume_disk_gb.to_i).to eq(0)
    end

    it "datastore resize → alert, row unchanged" do
      sign_in user
      db = create(:database_service, server: app_record.server, cpu: 0.25, memory_mb: 512, disk_gb: 10)
      db.app_databases.create!(app_record: app_record, alias_name: "DATABASE")
      patch "/dashboard/addons/#{db.id}/resize", params: { cpu: "0.5", memory_mb: "1024", disk_gb: "20" }
      expect(flash[:alert]).to eq("Custom sizing is not enabled on this server.")
      expect(db.reload.slice(:memory_mb, :disk_gb)).to eq("memory_mb" => 512, "disk_gb" => 10)
    end
  end

  describe "I3: flag on, counts go through ApplyChange" do
    before do
      app_record.dyno_allocations.destroy_all
      app_record.dyno_allocations.create!(process_type: "web", count: 1, cpu: 4.0, memory_mb: 8192)
      app_record.process_scales.find_or_create_by!(process_type: "web").update!(count: 1)
      refuse_resources!
      allow(Lifecycle::Ops).to receive(:converge!)
    end

    it "dashboard scaling#update refuses 1→10 when the enforcer says no" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 10 } }
      expect(flash[:alert]).to match(/limit/)
      expect(app_record.process_scales.find_by(process_type: "web").count).to eq(1)
      expect(Lifecycle::Ops).not_to have_received(:converge!)
    end

    it "API legacy scaling-only path refuses 1→10 when the enforcer says no" do
      patch "/api/v1/apps/#{app_record.id}/ps", params: { scaling: { web: 10 } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(app_record.process_scales.find_by(process_type: "web").count).to eq(1)
      expect(Lifecycle::Ops).not_to have_received(:converge!)
    end

    it "API combined path routes scaling-only types through ApplyChange too" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_call_original
      allow(Resources::ApplyChange).to receive(:call).and_call_original
      patch "/api/v1/apps/#{app_record.id}/ps",
        params: { resources: { web: { cpu: "4", memory_mb: "8192" } }, scaling: { worker: 2 } }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(Resources::ApplyChange).to have_received(:call).with(hash_including(
        processes: hash_including("worker" => hash_including(cpu: 4.0, memory_mb: 8192, count: "2"))
      ))
      expect(app_record.dyno_allocations.find_by(process_type: "worker").memory_mb).to eq(8192)
    end
  end

  describe "I5: refused sizing on create leaves no app" do
    before { refuse_resources! }

    it "dashboard create → 422 with the error, no AppRecord, no DNS" do
      sign_in user
      expect(Wokku.config.dns_provider).not_to receive(:create_app_record)
      post "/dashboard/apps", params: { app_record: { name: "refused-app", server_id: servers(:one).id },
                                        processes: { web: { cpu: "4", memory_mb: "8192", count: "1" } } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("over your account limit")
      expect(AppRecord.find_by(name: "refused-app")).to be_nil
    end

    it "API create → 422 json error, no AppRecord, no DNS" do
      expect(Wokku.config.dns_provider).not_to receive(:create_app_record)
      post api_v1_apps_path, params: { name: "refused-api-app", server_id: servers(:one).id,
                                       resources: { web: { cpu: "4", memory_mb: "8192", count: "1" } } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("over your account limit")
      expect(AppRecord.find_by(name: "refused-api-app")).to be_nil
    end
  end

  it "I7: builder renders on the new-app form with Bundle v2 off" do
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
    sign_in user
    get "/dashboard/apps/new"
    expect(response.body).to include("processes[web][cpu]")
  end

  describe "M2: non-hash params never 500" do
    it "API ps#update with a string resources → 422" do
      patch "/api/v1/apps/#{app_record.id}/ps", params: { resources: "junk" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "API ps#update with a string process entry → 422" do
      patch "/api/v1/apps/#{app_record.id}/ps", params: { resources: { web: "junk" } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "API apps#create with a string resources → 422 invalid_params" do
      post api_v1_apps_path, params: { name: "junk-res-app", server_id: servers(:one).id, resources: "junk" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AppRecord.find_by(name: "junk-res-app")).to be_nil
    end

    it "dashboard resources#update with a string processes → alert" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/resources", params: { processes: "junk" }
      expect(flash[:alert]).to be_present
    end

    it "dashboard create with a string processes → 422, no app" do
      sign_in user
      post "/dashboard/apps", params: { app_record: { name: "junk-proc-app", server_id: servers(:one).id }, processes: "junk" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AppRecord.find_by(name: "junk-proc-app")).to be_nil
    end
  end
end
