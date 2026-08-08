require "rails_helper"

RSpec.describe Git::PushDeployer do
  let(:app) { create(:app_record, wokkud_git: true) }
  let(:repo) { Git::BareRepo.new(app.name).ensure! }
  let(:sha) do
    work = Dir.mktmpdir
    system("git", "-C", work, "init", "--quiet", "-b", "main", exception: true)
    File.write(File.join(work, "hello.txt"), "hi")
    system("git", "-C", work, "add", ".", exception: true)
    system("git", "-C", work, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init", exception: true)
    system("git", "-C", work, "push", "--quiet", repo.path, "main", exception: true)
    `git -C #{repo.path} rev-parse main`.strip
  end

  before do
    allow(Wokku.config.backup_store).to receive(:put)
  end

  around do |ex| # same WOKKU_GIT_REPO_ROOT tmpdir idiom as bare_repo_spec
    Dir.mktmpdir do |root|
      old = ENV["WOKKU_GIT_REPO_ROOT"]; ENV["WOKKU_GIT_REPO_ROOT"] = root
      ex.run
      ENV["WOKKU_GIT_REPO_ROOT"] = old
    end
  end

  it "creates a pending Deploy with archive_key and enqueues TarballDeployJob" do
    deploy = nil
    expect {
      deploy = described_class.new(app, sha: sha, ref: "refs/heads/main").call
    }.to have_enqueued_job(TarballDeployJob).with(app_id: app.id, deploy_id: anything)
    expect(deploy).to be_pending
    expect(deploy.commit_sha).to eq(sha)
    expect(deploy.archive_key).to match(%r{\Adeploy-archives/#{app.id}/[0-9a-f-]+\.tar\.gz\z})
  end

  it "refuses non-main refs with a typed code" do
    expect { described_class.new(app, sha: sha, ref: "refs/heads/feature").call }
      .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:ref_not_deployable) }
  end

  it "refuses when a deploy is in flight" do
    create(:deploy, app_record: app, status: :building)
    expect { described_class.new(app, sha: sha, ref: "refs/heads/main").call }
      .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:deploy_in_progress) }
  end

  it "reuses a provided deploy row and skips the gates" do
    create(:deploy, app_record: app, status: :building) # would trip the guard
    row = create(:deploy, app_record: app, status: :pending)
    got = described_class.new(app, sha: sha, ref: "refs/heads/anybranch", deploy: row).call
    expect(got.id).to eq(row.id)
    expect(got.archive_key).to be_present
  end

  it "wraps archive failures typed, leaking no Deploy row" do
    bogus_sha = "1234567890abcdef1234567890abcdef12345678" # valid hex, no such object
    expect {
      expect { described_class.new(app, sha: bogus_sha, ref: "refs/heads/main").call }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:archive_failed) }
    }.not_to change(Deploy, :count)
  end

  it "treats an all-zero sha (branch deletion) as a friendly typed refusal, leaking no Deploy row" do
    expect {
      expect { described_class.new(app, sha: "0" * 40, ref: "refs/heads/main").call }
        .to raise_error(described_class::Error) { |e|
          expect(e.error_code).to eq(:ref_not_deployable)
          expect(e.message).to match(/branch deletion/i)
        }
    }.not_to change(Deploy, :count)
  end

  it "rejects a non-hex sha before it reaches git argv (no flag smuggling)" do
    expect {
      expect { described_class.new(app, sha: "--output=/tmp/evil", ref: "refs/heads/main").call }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:ref_not_deployable) }
    }.not_to change(Deploy, :count)
  end
end
