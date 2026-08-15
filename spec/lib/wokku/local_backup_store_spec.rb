require "rails_helper"

RSpec.describe Wokku::Providers::LocalBackupStore do
  around do |ex|
    Dir.mktmpdir do |dir|
      orig = ENV["WOKKU_BACKUP_PATH"]
      ENV["WOKKU_BACKUP_PATH"] = dir
      ex.run
    ensure
      ENV["WOKKU_BACKUP_PATH"] = orig
    end
  end

  subject(:store) { described_class.new }

  it "round-trips put/exists?/list_keys/delete on the local filesystem" do
    expect(store.configured?).to be(true)
    expect(store.exists?("a/b/one.tar.gz")).to be(false)

    store.put("a/b/one.tar.gz", StringIO.new("bytes"))
    store.put("a/b/two.tar.gz", StringIO.new("more"))
    store.put("other/x.dump", StringIO.new("dump"))

    expect(store.exists?("a/b/one.tar.gz")).to be(true)
    expect(store.list_keys("a/")).to match_array(%w[a/b/one.tar.gz a/b/two.tar.gz])

    store.delete("a/b/one.tar.gz")
    expect(store.exists?("a/b/one.tar.gz")).to be(false)
    expect { store.delete("a/b/one.tar.gz") }.not_to raise_error # idempotent like S3
  end

  it "cannot presign (OSS remote-upload flow is Phase 3)" do
    expect(store.presigned_put("k")).to be_nil
    expect(store.presigned_get("k")).to be_nil
  end

  it "lists dotfile keys (retention must be able to prune them)" do
    store.put("a/.hidden.tar.gz", StringIO.new("x"))
    expect(store.list_keys("a/")).to eq([ "a/.hidden.tar.gz" ])
  end

  it "tolerates a trailing slash in WOKKU_BACKUP_PATH" do
    ENV["WOKKU_BACKUP_PATH"] = "#{ENV['WOKKU_BACKUP_PATH']}/"
    store.put("a/one.tar.gz", StringIO.new("x"))
    expect(store.list_keys("a/")).to eq([ "a/one.tar.gz" ])
  end

  it "rejects path traversal in keys" do
    expect { store.put("../evil", StringIO.new("x")) }.to raise_error(ArgumentError)
    expect { store.exists?("a/../../evil") }.to raise_error(ArgumentError)
  end
end
