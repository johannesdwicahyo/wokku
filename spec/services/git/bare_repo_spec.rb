require "rails_helper"

RSpec.describe Git::BareRepo do
  around do |ex|
    Dir.mktmpdir do |root|
      @root = root
      ClimateControl.modify(WOKKU_GIT_REPO_ROOT: root) { ex.run }
    rescue NameError # climate_control not bundled — use plain env swap
      old = ENV["WOKKU_GIT_REPO_ROOT"]; ENV["WOKKU_GIT_REPO_ROOT"] = root
      ex.run
      ENV["WOKKU_GIT_REPO_ROOT"] = old
    end
  end

  subject(:repo) { described_class.new("myapp") }

  it "initializes a bare repo with hook and pack cap, idempotently" do
    repo.ensure!
    expect(File).to exist(File.join(repo.path, "HEAD"))
    hook = File.join(repo.path, "hooks", "post-receive")
    expect(File.executable?(hook)).to be(true)
    expect(File.read(hook)).to include("wokku-git-post-receive")
    expect(`git -C #{repo.path} config receive.maxInputSize`.strip).to eq("536870912")
    expect { repo.ensure! }.not_to change { File.mtime(File.join(repo.path, "HEAD")) }
  end

  it "removes the repo dir" do
    repo.ensure!
    repo.remove!
    expect(repo.exists?).to be(false)
  end

  it "refuses unsafe names" do
    expect { described_class.new("../evil") }.to raise_error(ArgumentError)
  end
end
