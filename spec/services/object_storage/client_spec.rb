require "rails_helper"

RSpec.describe ObjectStorage::Client do
  let(:base) { "http://rustfs.test:9100" }
  let(:admin) { "#{base}/rustfs/admin/v3" }
  let(:client) { described_class.new(endpoint: base, access_key: "AK", secret_key: "SK") }
  let(:auth) { { "Authorization" => /\AAWS4-HMAC-SHA256 / } }

  it "create_bucket PUTs /<name>, treating BucketAlreadyOwnedByYou as success" do
    stub = stub_request(:put, "#{base}/b1").with(headers: auth).to_return(status: 200)
    expect(client.create_bucket("b1")).to be true
    expect(stub).to have_been_requested
    stub_request(:put, "#{base}/b2").to_return(status: 409, body: "<Error><Code>BucketAlreadyOwnedByYou</Code><Message>x</Message></Error>")
    expect(client.create_bucket("b2")).to be true
  end

  it "create_bucket raises on other 409s" do
    stub_request(:put, "#{base}/b3").to_return(status: 409, body: "<Error><Code>BucketAlreadyExists</Code><Message>taken</Message></Error>")
    expect { client.create_bucket("b3") }.to raise_error(ObjectStorage::Error, /taken/)
  end

  it "delete_bucket! force-deletes" do
    stub = stub_request(:delete, "#{base}/b1").with(headers: auth.merge("X-Rustfs-Force-Delete" => "true")).to_return(status: 204)
    expect(client.delete_bucket!("b1")).to be true
    expect(stub).to have_been_requested
  end

  it "add_user" do
    stub = stub_request(:put, "#{admin}/add-user").with(query: { accessKey: "u" }, headers: auth,
      body: { secretKey: "s", status: "enabled" }.to_json).to_return(status: 200)
    expect(client.add_user("u", "s")).to be true
    expect(stub).to have_been_requested
  end

  it "remove_user" do
    stub = stub_request(:delete, "#{admin}/remove-user").with(query: { accessKey: "u" }, headers: auth).to_return(status: 200)
    expect(client.remove_user("u")).to be true
    expect(stub).to have_been_requested
  end

  it "put_policy grants only object/listing actions (no policy, ACL, versioning, lock, replication)" do
    sent = nil
    stub = stub_request(:put, "#{admin}/add-canned-policy").with(query: { name: "p" }, headers: auth) { |req|
      sent = JSON.parse(req.body)["Statement"]
    }.to_return(status: 200)
    expect(client.put_policy("p", "b")).to be true
    expect(stub).to have_been_requested
    expect(sent.size).to eq(1)
    st = sent.first
    expect(st["Effect"]).to eq("Allow")
    expect(st["Resource"]).to eq([ "arn:aws:s3:::b", "arn:aws:s3:::b/*" ])
    expect(st["Action"]).to match_array(%w[s3:GetObject s3:PutObject s3:DeleteObject s3:ListBucket
      s3:ListBucketMultipartUploads s3:ListMultipartUploadParts s3:AbortMultipartUpload s3:GetBucketLocation])
    expect(st["Action"].grep(/\*|Policy|Acl|Versioning|ObjectLock|Replication|Retention|LegalHold/)).to be_empty
  end

  it "remove_policy" do
    stub = stub_request(:delete, "#{admin}/remove-canned-policy").with(query: { name: "p" }, headers: auth).to_return(status: 200)
    expect(client.remove_policy("p")).to be true
    expect(stub).to have_been_requested
  end

  it "attach_policy" do
    stub = stub_request(:put, "#{admin}/set-user-or-group-policy")
      .with(query: { policyName: "p", userOrGroup: "u", isGroup: "false" }, headers: auth).to_return(status: 200)
    expect(client.attach_policy("p", "u")).to be true
    expect(stub).to have_been_requested
  end

  it "set_quota" do
    stub = stub_request(:put, "#{admin}/set-bucket-quota").with(query: { bucket: "b" }, headers: auth,
      body: { quota: 2 * 1024**3, quotatype: "hard" }.to_json).to_return(status: 200)
    expect(client.set_quota("b", 2)).to be true
    expect(stub).to have_been_requested
  end

  it "usage maps bucket to bytes" do
    stub_request(:get, "#{admin}/datausageinfo").with(headers: auth)
      .to_return(status: 200, body: { buckets_usage: { "mcloud" => { size: 0 }, "big" => { size: 2147483648 } } }.to_json)
    expect(client.usage).to eq("mcloud" => 0, "big" => 2147483648)
  end

  it "raises ObjectStorage::Error with status and message on non-2xx" do
    stub_request(:get, "#{admin}/datausageinfo").to_return(status: 403, body: "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>")
    expect { client.usage }.to raise_error(ObjectStorage::Error, /403.*Access Denied/)
  end

  it "defaults from Wokku.config.object_storage" do
    Wokku.config.object_storage = { endpoint: base, access_key: "A", secret_key: "S" }
    expect(Wokku.config.object_storage?).to be true
    stub_request(:get, "#{admin}/datausageinfo").to_return(status: 200, body: "{}")
    expect(described_class.new.usage).to eq({})
  ensure
    Wokku.config.object_storage = nil
  end

  it "wraps transport failures as ObjectStorage::Error without secrets" do
    stub_request(:put, "#{base}/b9").to_raise(Errno::ECONNREFUSED)
    expect { client.create_bucket("b9") }.to raise_error(ObjectStorage::Error) { |e| expect(e.message).not_to include("SK") }
  end

  it "treats 404 as success for remove_user, remove_policy and delete_bucket! (retry-safe)" do
    stub_request(:delete, "#{admin}/remove-user").with(query: { accessKey: "u" }).to_return(status: 404, body: "<Error><Code>NoSuchUser</Code></Error>")
    stub_request(:delete, "#{admin}/remove-canned-policy").with(query: { name: "p" }).to_return(status: 404, body: "{}")
    stub_request(:delete, "#{base}/gone").to_return(status: 404, body: "<Error><Code>NoSuchBucket</Code></Error>")
    expect(client.remove_user("u")).to be true
    expect(client.remove_policy("p")).to be true
    expect(client.delete_bucket!("gone")).to be true
  end
end
