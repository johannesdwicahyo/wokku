require "rails_helper"

RSpec.describe "PublicCliController", type: :request do
  it "returns a gzipped tarball with CLI files" do
    get "/cli/wokku.tar.gz"
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("application/gzip")
    expect(response.body.bytes[0, 2]).to eq([ 0x1f, 0x8b ])
    expect(response.headers["Content-Disposition"]).to match(/wokku-cli\.tar\.gz/)

    Tempfile.create([ "wokku-test", ".tar.gz" ]) do |f|
      f.binmode
      f.write(response.body)
      f.flush
      entries = `tar -tzf #{f.path}`.lines.map(&:strip)
      expect(entries).to include("wokku")
      expect(entries).to include("VERSION")
      expect(entries.any? { |e| e.start_with?("lib/wokku/") }).to be true
      expect(entries.any? { |e| e.start_with?("lib/wokku/commands/") }).to be true
    end
  end

  it "incorporates VERSION into the cache key" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    get "/cli/wokku.tar.gz"
    expect(response).to have_http_status(:success)
    cache_key = "wokku-cli-tarball-v#{File.read(Rails.root.join('legacy_cli', 'VERSION')).strip}"
    expect(Rails.cache.exist?(cache_key)).to be true
  ensure
    Rails.cache = original_cache if original_cache
  end
end
