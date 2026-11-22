# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API object storage", type: :request do
  include ActiveJob::TestHelper

  let(:app_record) { app_records(:one) }
  let(:url) { "/api/v1/apps/#{app_record.id}/object_storage" }

  def user_with(role)
    create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: role) }
  end

  def auth(user) = { "Authorization" => "Bearer #{api_v1_token_for(user)}" }

  let(:member) { user_with(:member) }

  before { Wokku.config.object_storage = { endpoint: "https://s3.example.test", access_key: "A", secret_key: "S" } }
  after { Wokku.config.object_storage = nil }
  before { allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(false) }

  context "when the feature is off" do
    before { Wokku.config.object_storage = nil }

    it "404s every action" do
      get url, headers: auth(member)
      expect(response).to have_http_status(:not_found)
      post url, headers: auth(member)
      expect(response).to have_http_status(:not_found)
      post "#{url}/rotate", headers: auth(member)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST" do
    it "creates and returns 202 provisioning" do
      expect { post url, headers: auth(member) }.to have_enqueued_job(ObjectStorage::ProvisionJob)
      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body).to include("status" => "provisioning", "price_idr_per_gb" => 400, "free_gb" => 1,
                              "endpoint" => "https://s3.example.test", "region" => "us-east-1")
      expect(body["secret_access_key"]).to be_present
    end

    it "409s when the app already has a bucket" do
      create(:object_storage_bucket, app_record: app_record)
      post url, headers: auth(member)
      expect(response).to have_http_status(:conflict)
    end

    it "403s a free team whose 1 GB already went to another app" do
      allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(true)
      create(:object_storage_bucket, app_record: create(:app_record, team: app_record.team), quota_gb: 1)
      expect { post url, headers: auth(member) }.not_to have_enqueued_job(ObjectStorage::ProvisionJob)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("1 GB")
    end

    it "lets a paid team add a bucket to a second app" do
      create(:object_storage_bucket, app_record: create(:app_record, team: app_record.team))
      post url, headers: auth(member)
      expect(response).to have_http_status(:accepted)
    end

    it "403s for a viewer" do
      post url, headers: auth(user_with(:viewer))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET" do
    let!(:bucket) { create(:object_storage_bucket, app_record: app_record) }

    it "returns the full payload to a member" do
      get url, headers: auth(member)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("bucket" => bucket.name, "access_key_id" => bucket.access_key,
                                              "secret_access_key" => bucket.secret_key, "quota_gb" => 10, "used_gb" => 0.0)
    end

    it "omits the secret key entirely for a viewer" do
      get url, headers: auth(user_with(:viewer))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("secret_access_key")
      expect(response.body).not_to include(bucket.secret_key)
    end

    it "404s when the app has none" do
      bucket.destroy!
      get url, headers: auth(member)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH" do
    let!(:bucket) { create(:object_storage_bucket, app_record: app_record) }

    before { allow(ObjectStorage::Provisioner).to receive(:resize!) { |b, gb| b.update!(quota_gb: gb) } }

    it "resizes" do
      patch url, params: { quota_gb: 50 }, headers: auth(member)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["quota_gb"]).to eq(50)
    end

    [ 0, 2000 ].each do |gb|
      it "422s for #{gb}" do
        patch url, params: { quota_gb: gb }, headers: auth(member)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("must be between 1 and 1024 GB")
      end
    end

    it "403s a free team above 1 GB" do
      allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(true)
      patch url, params: { quota_gb: 5 }, headers: auth(member)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Free plan storage is fixed at 1 GB")
    end

    it "403s a viewer" do
      patch url, params: { quota_gb: 5 }, headers: auth(user_with(:viewer))
      expect(response).to have_http_status(:forbidden)
    end

    it "409s while the bucket is not active" do
      bucket.update!(status: "provisioning")
      patch url, params: { quota_gb: 50 }, headers: auth(member)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("Object storage is not ready (status: provisioning)")
      expect(ObjectStorage::Provisioner).not_to have_received(:resize!)
    end

    it "503s when RustFS is unavailable" do
      allow(ObjectStorage::Provisioner).to receive(:resize!).and_raise(ObjectStorage::Error, "down")
      patch url, params: { quota_gb: 50 }, headers: auth(member)
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to eq("Object storage is temporarily unavailable, try again shortly")
    end
  end

  describe "rotate and delete" do
    let!(:bucket) { create(:object_storage_bucket, app_record: app_record) }

    it "rotate enqueues and 202s" do
      expect { post "#{url}/rotate", headers: auth(member) }.to have_enqueued_job(ObjectStorage::RotateJob).with(bucket.id)
      expect(response).to have_http_status(:accepted)
    end

    it "rotate 409s while the bucket is not active" do
      bucket.update!(status: "failed")
      expect { post "#{url}/rotate", headers: auth(member) }.not_to have_enqueued_job(ObjectStorage::RotateJob)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("Object storage is not ready (status: failed)")
    end

    it "delete marks deleting, enqueues, 202s" do
      expect { delete url, headers: auth(member) }.to have_enqueued_job(ObjectStorage::DeprovisionJob).with(bucket.id)
      expect(response).to have_http_status(:accepted)
      expect(bucket.reload.status).to eq("deleting")
    end
  end
end
