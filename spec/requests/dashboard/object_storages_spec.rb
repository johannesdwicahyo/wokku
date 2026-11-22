# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard object storage", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:app_record) { app_records(:one) }
  let(:base) { "/dashboard/apps/#{app_record.id}/object_storage" }

  def user_with(role)
    create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: role) }
  end

  before { Wokku.config.object_storage = { endpoint: "https://s3.example.test", access_key: "A", secret_key: "S" } }
  after { Wokku.config.object_storage = nil }
  before { allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(false) }

  describe "resources page" do
    it "offers enable when none exists" do
      sign_in user_with(:member)
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response.body).to include("Object storage").and include("Enable object storage")
      expect(response.body).not_to include("MinIO")
    end

    it "shows the bucket with the secret hidden for a viewer" do
      b = create(:object_storage_bucket, app_record: app_record)
      sign_in user_with(:viewer)
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response.body).to include(b.name).and include("hidden")
      expect(response.body).not_to include(b.secret_key)
    end

    it "omits the section when the feature is off" do
      Wokku.config.object_storage = nil
      sign_in user_with(:member)
      get "/dashboard/apps/#{app_record.id}/resources"
      expect(response.body).not_to include("Enable object storage")
    end
  end

  describe "overview card" do
    it "renders the copy" do
      create(:object_storage_bucket, app_record: app_record, quota_gb: 10)
      sign_in user_with(:member)
      get "/dashboard/apps/#{app_record.id}"
      expect(response.body).to include("Object storage · S3-compatible · 0.0 GB of 10 GB · Rp 400/GB per month after 1 GB free per account")
    end
  end

  describe "reveal" do
    let!(:bucket) { create(:object_storage_bucket, app_record: app_record) }

    it "shows the secret to a member, audited, uncached" do
      sign_in user_with(:member)
      expect { post "#{base}/reveal" }.to change { Activity.where(action: "object_storage.revealed").count }.by(1)
      expect(response.body).to include(bucket.secret_key)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "files the audit under the app's team for a multi-team user" do
      user = user_with(:member)
      other = create(:team)
      create(:team_membership, user: user, team: other, role: :admin)
      sign_in user
      post "#{base}/reveal"
      expect(Activity.find_by!(action: "object_storage.revealed").team).to eq(app_record.team)
    end

    it "has no GET reveal route" do
      sign_in user_with(:member)
      get base
      expect(response).to have_http_status(:not_found)
    end

    it "refuses a viewer" do
      sign_in user_with(:viewer)
      post "#{base}/reveal"
      expect(response.body).not_to include(bucket.secret_key)
      expect(Activity.where(action: "object_storage.revealed")).to be_empty
    end
  end

  describe "writes" do
    before { sign_in user_with(:member) }

    it "creates" do
      expect { post base }.to have_enqueued_job(ObjectStorage::ProvisionJob)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/resources")
    end

    it "refuses a free team's second app once its 1 GB is in use" do
      allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(true)
      create(:object_storage_bucket, app_record: create(:app_record, team: app_record.team), quota_gb: 1)
      expect { post base }.not_to have_enqueued_job(ObjectStorage::ProvisionJob)
      expect(flash[:alert]).to include("1 GB")
    end

    it "resizes" do
      b = create(:object_storage_bucket, app_record: app_record)
      allow(ObjectStorage::Provisioner).to receive(:resize!) { |bk, gb| bk.update!(quota_gb: gb) }
      patch base, params: { quota_gb: 20 }
      expect(b.reload.quota_gb).to eq(20)
    end

    it "rejects an out-of-range resize" do
      b = create(:object_storage_bucket, app_record: app_record)
      patch base, params: { quota_gb: 5000 }
      expect(b.reload.quota_gb).to eq(10)
      expect(flash[:alert]).to include("must be between 1 and 1024 GB")
    end

    it "refuses resize and rotate while the bucket is not active" do
      b = create(:object_storage_bucket, app_record: app_record, status: "provisioning")
      expect(ObjectStorage::Provisioner).not_to receive(:resize!)
      patch base, params: { quota_gb: 20 }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/resources")
      expect(flash[:alert]).to eq("Object storage is not ready (status: provisioning)")
      expect { post "#{base}/rotate" }.not_to have_enqueued_job(ObjectStorage::RotateJob)
      expect(flash[:alert]).to eq("Object storage is not ready (status: provisioning)")
      expect(b.reload.quota_gb).to eq(10)
    end

    it "alerts instead of erroring when RustFS is unavailable on resize" do
      create(:object_storage_bucket, app_record: app_record)
      allow(ObjectStorage::Provisioner).to receive(:resize!).and_raise(ObjectStorage::Error, "down")
      patch base, params: { quota_gb: 20 }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/resources")
      expect(flash[:alert]).to eq("Object storage is temporarily unavailable, try again shortly")
    end

    it "rotates and deletes via jobs" do
      b = create(:object_storage_bucket, app_record: app_record)
      expect { post "#{base}/rotate" }.to have_enqueued_job(ObjectStorage::RotateJob)
      expect { delete base }.to have_enqueued_job(ObjectStorage::DeprovisionJob)
      expect(b.reload.status).to eq("deleting")
    end

    it "404s when off" do
      Wokku.config.object_storage = nil
      post base
      expect(response).to have_http_status(:not_found)
    end
  end
end
