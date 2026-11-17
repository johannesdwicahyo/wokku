require "rails_helper"
require "aws-sdk-s3"

RSpec.describe BackupDestination, "#verify_connection!" do
  let(:dest) { BackupDestination.new(server: servers(:one), provider: "minio", bucket: "b", path_prefix: "dbs/x",
                                     endpoint_url: "https://s3.example.test", access_key_id: "k", secret_access_key: "s") }

  it "writes and deletes a small test object" do
    client = Aws::S3::Client.new(stub_responses: true)
    allow(dest).to receive(:s3_client).and_return(client)
    dest.verify_connection!
    ops = client.api_requests.map { |r| [ r[:operation_name], r[:params][:key] ] }
    expect(ops).to eq([ [ :put_object, "dbs/x/.wokku-connection-test" ], [ :delete_object, "dbs/x/.wokku-connection-test" ] ])
  end

  it "turns S3 errors into a message an admin can act on" do
    client = Aws::S3::Client.new(stub_responses: { put_object: "NoSuchBucket" })
    allow(dest).to receive(:s3_client).and_return(client)
    expect { dest.verify_connection! }.to raise_error(BackupDestination::ConnectionError, /bucket "b" doesn't exist/)

    client = Aws::S3::Client.new(stub_responses: { put_object: "AccessDenied" })
    allow(dest).to receive(:s3_client).and_return(client)
    expect { dest.verify_connection! }.to raise_error(BackupDestination::ConnectionError, /Access denied/)
  end

  it "reports an unreachable endpoint" do
    allow(dest).to receive(:s3_client).and_raise(Seahorse::Client::NetworkingError.new(SocketError.new("getaddrinfo")))
    expect { dest.verify_connection! }.to raise_error(BackupDestination::ConnectionError, /Can't reach/)
  end
end
