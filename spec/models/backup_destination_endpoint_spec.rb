# frozen_string_literal: true

require "rails_helper"

# Security assessment 2026-11-19, F-06: saving a destination makes the control
# plane send requests to endpoint_url (the connection test, every backup), so
# it must not point at internal addresses (loopback, cloud metadata, private
# networks) unless the operator opts in for a LAN MinIO.
RSpec.describe BackupDestination, "endpoint_url" do
  let(:server) { create(:server) }

  def destination(url)
    server.build_backup_destination(provider: "minio", bucket: "b", endpoint_url: url)
  end

  def errors_for(url)
    d = destination(url)
    d.valid?
    d.errors[:endpoint_url]
  end

  it "accepts a public https endpoint" do
    allow(Resolv).to receive(:getaddresses).with("s3.example.com").and_return([ "93.184.216.34" ])
    expect(errors_for("https://s3.example.com")).to be_empty
  end

  it "accepts a blank endpoint (AWS S3 default)" do
    expect(errors_for("")).to be_empty
  end

  it "rejects non-http schemes and embedded credentials" do
    expect(errors_for("file:///etc/passwd")).not_to be_empty
    expect(errors_for("ftp://s3.example.com")).not_to be_empty
    expect(errors_for("https://user:pw@s3.example.com")).not_to be_empty
    expect(errors_for("not a url")).not_to be_empty
  end

  {
    "loopback" => "http://127.0.0.1:9000",
    "IPv6 loopback" => "http://[::1]:9000",
    "cloud metadata" => "http://169.254.169.254/latest/meta-data",
    "private 10/8" => "http://10.0.0.5:9000",
    "private 172.16/12" => "http://172.18.0.2:9000",
    "private 192.168/16" => "http://192.168.1.10:9000",
    "carrier NAT" => "http://100.64.0.1:9000",
    "unspecified" => "http://0.0.0.0:9000",
    "IPv4-mapped loopback" => "http://[::ffff:127.0.0.1]:9000"
  }.each do |label, url|
    it "rejects a #{label} address" do
      expect(errors_for(url).join).to include("internal")
    end
  end

  it "rejects a hostname that resolves to an internal address" do
    allow(Resolv).to receive(:getaddresses).with("evil.example.com").and_return([ "93.184.216.34", "127.0.0.1" ])
    expect(errors_for("https://evil.example.com").join).to include("internal")
  end

  it "allows a private address when the operator opts in (LAN MinIO)" do
    stub_const("ENV", ENV.to_h.merge("WOKKU_ALLOW_PRIVATE_BACKUP_ENDPOINT" => "1"))
    expect(errors_for("http://192.168.1.10:9000")).to be_empty
    expect(errors_for("http://169.254.169.254")).not_to be_empty # metadata stays blocked
  end

  it "only re-checks when the endpoint changes" do
    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ])
    d = destination("https://s3.example.com")
    d.save!
    expect(Resolv).not_to receive(:getaddresses)
    d.update!(retention_days: 7)
  end
end
