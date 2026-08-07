require "rails_helper"

RSpec.describe AppRecord, "git_provider validations" do
  it "accepts a known provider with repo" do
    app = build(:app_record, git_provider: "gitlab", git_repo_full_name: "octo/repo")
    expect(app).to be_valid
  end

  it "rejects an unknown provider" do
    app = build(:app_record, git_provider: "fakehub", git_repo_full_name: "x/y")
    expect(app).not_to be_valid
    expect(app.errors[:git_provider]).to be_present
  end

  it "rejects a provider without a repo name" do
    app = build(:app_record, git_provider: "gitlab", git_repo_full_name: nil)
    expect(app).not_to be_valid
    expect(app.errors[:git_repo_full_name]).to be_present
  end

  it "allows nil provider (app not connected to any repo)" do
    app = build(:app_record, git_provider: nil, git_repo_full_name: nil)
    expect(app).to be_valid
  end

  it "exposes SUPPORTED_GIT_PROVIDERS" do
    expect(AppRecord::SUPPORTED_GIT_PROVIDERS).to eq(%w[github gitlab bitbucket])
  end
end
