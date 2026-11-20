# frozen_string_literal: true

require "rails_helper"

# Security assessment 2026-11-19, F-10: agents authenticate with
# Server#ingest_token. Look it up by its SHA-256 digest, so the DB comparison
# can't be timed to recover the token byte by byte.
RSpec.describe Server, "ingest token lookup" do
  let(:server) { create(:server) }

  it "stores the digest of the token and finds the server by token" do
    expect(server.ingest_token_digest).to eq(Digest::SHA256.hexdigest(server.ingest_token))
    expect(Server.find_by_ingest_token(server.ingest_token)).to eq(server)
  end

  it "finds nothing for a wrong, blank or nil token" do
    server
    expect(Server.find_by_ingest_token("nope")).to be_nil
    expect(Server.find_by_ingest_token("")).to be_nil
    expect(Server.find_by_ingest_token(nil)).to be_nil
  end

  it "follows a rotation" do
    old = server.ingest_token
    server.update!(ingest_token: nil)
    expect(Server.find_by_ingest_token(old)).to be_nil
    expect(Server.find_by_ingest_token(server.ingest_token)).to eq(server)
  end

  it "matches the fixtures' digests (fixtures skip callbacks)" do
    expect(Server.find_by_ingest_token(servers(:one).ingest_token)).to eq(servers(:one))
  end

  it "no agent endpoint looks the token up by plain equality" do
    offenders = Dir[Rails.root.join("..", "app", "**", "*.rb")].select { |f| File.read(f).match?(/find_by\(\s*ingest_token:/) }
    expect(offenders).to be_empty
  end
end
