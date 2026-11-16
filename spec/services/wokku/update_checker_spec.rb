require "rails_helper"

# Self-host update reminder: the newest release is the version label on the
# public ghcr image's :latest tag (no phone-home to wokku.cloud).
RSpec.describe Wokku::UpdateChecker do
  let(:reg) { "https://ghcr.io/v2/johannesdwicahyo/wokku" }

  def stub_registry(version:)
    stub_request(:get, %r{ghcr.io/token}).to_return(body: { token: "t" }.to_json)
    stub_request(:get, "#{reg}/manifests/latest").to_return(body: {
      mediaType: "application/vnd.oci.image.index.v1+json",
      manifests: [ { digest: "sha256:arm", platform: { architecture: "arm64" } },
                   { digest: "sha256:amd", platform: { architecture: "amd64" } } ]
    }.to_json)
    stub_request(:get, "#{reg}/manifests/sha256:amd").to_return(body: { config: { digest: "sha256:cfg" } }.to_json)
    stub_request(:get, "#{reg}/blobs/sha256:cfg").to_return(body: {
      config: { Labels: { "org.opencontainers.image.version" => version } }
    }.to_json)
  end

  it "reads the version label of the published :latest image" do
    stub_registry(version: "2026.11.20-abc1234")
    expect(described_class.latest_version).to eq("2026.11.20-abc1234")
  end

  it "returns nil when the registry can't be reached" do
    stub_request(:get, %r{ghcr.io/token}).to_timeout
    expect(described_class.latest_version).to be_nil
  end

  describe ".newer?" do
    it "is true for a later release" do
      expect(described_class.newer?("2026.11.20-abc1234", "2026.11.16-f698248")).to be(true)
      expect(described_class.newer?("2026.11.16-bbbbbbb", "2026.11.16-aaaaaaa")).to be(true) # same day, new build
    end

    it "is false for the same, an older, or an unknown version" do
      expect(described_class.newer?("2026.11.16-f698248", "2026.11.16-f698248")).to be(false)
      expect(described_class.newer?("2026.11.10-abc1234", "2026.11.16-f698248")).to be(false)
      expect(described_class.newer?(nil, "2026.11.16-f698248")).to be(false)
      expect(described_class.newer?("2026.11.20-abc1234", "dev")).to be(false)
    end
  end
end
