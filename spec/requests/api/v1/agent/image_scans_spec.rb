# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Agent::ImageScans" do
  let(:server) { create(:server) }
  let(:app_record) { create(:app_record, server: server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}", "CONTENT_TYPE" => "application/json" } }
  let!(:scan) { ImageScan.create!(app_record: app_record, server: server, image_ref: "127.0.0.1:5000/wokku/x:1") }

  describe "claim" do
    it "returns the image and marks it claimed" do
      post "/api/v1/agent/image_scans/#{scan.id}/claim", headers: headers
      expect(response.parsed_body).to eq("image_ref" => scan.image_ref, "timeout_seconds" => 300)
      expect(scan.reload).to be_claimed
    end

    it "is 409 the second time" do
      2.times { post "/api/v1/agent/image_scans/#{scan.id}/claim", headers: headers }
      expect(response).to have_http_status(:conflict)
    end

    it "is 404 for another server's scan" do
      other = create(:server)
      post "/api/v1/agent/image_scans/#{scan.id}/claim", headers: { "Authorization" => "Bearer #{other.ingest_token}" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "report" do
    before { scan.update!(status: :claimed, claimed_at: Time.current) }

    let(:findings) { Array.new(60) { |i| { id: "CVE-#{i}", package: "p", installed: "1", fixed: "2", severity: "HIGH", title: "t" * 400 } } }

    it "stores counts and at most 50 truncated findings, then runs AfterReport" do
      allow(ImageScans::AfterReport).to receive(:call)
      post "/api/v1/agent/image_scans/#{scan.id}/report", headers: headers,
           params: { status: "succeeded", counts: { critical: 1, high: 2, bogus: 9 }, findings: findings, scanner_version: "0.58", db_updated_at: "2026-11-26T00:00:00Z" }.to_json
      expect(response).to have_http_status(:ok)
      scan.reload
      expect(scan).to be_succeeded
      expect(scan.counts).to include("critical" => 1, "high" => 2, "fixable" => 0)
      expect(scan.counts).not_to have_key("bogus")
      expect(scan.findings.size).to eq(50)
      expect(scan.findings.first["title"].size).to eq(160)
      expect(ImageScans::AfterReport).to have_received(:call).with(scan)
    end

    it "records a failure, mapping unknown error codes" do
      post "/api/v1/agent/image_scans/#{scan.id}/report", headers: headers, params: { status: "failed", error_code: "weird", error: "x" }.to_json
      expect(scan.reload).to have_attributes(status: "failed", error_code: "unknown")
      post "/api/v1/agent/image_scans/#{scan.id}/report", headers: headers, params: { status: "failed", error_code: "oom" }.to_json
      expect(scan.reload.error_code).to eq("oom")
    end

    it "drops a report for a deleted app with 200" do
      id = scan.id
      app_record.destroy!
      post "/api/v1/agent/image_scans/#{id}/report", headers: headers, params: { status: "succeeded" }.to_json
      expect(response).to have_http_status(:ok)
      expect(ImageScan.count).to eq(0)
    end
  end

  describe "heartbeat" do
    it "lists at most one pending scan id, only for that server" do
      other_app = create(:app_record, server: server)
      ImageScan.create!(app_record: other_app, server: server, image_ref: "r/y:1")
      ImageScan.create!(app_record: create(:app_record), server: create(:server), image_ref: "r/z:1")
      allow(Wokku.config).to receive(:image_scans?).and_return(true)
      post "/api/v1/agent/heartbeat", headers: headers, params: { vitals: { cpu: 1 } }.to_json
      expect(response.parsed_body["pending_image_scan_ids"].size).to eq(1)
    end
  end
end
