require "rails_helper"

RSpec.describe Preview::Commenter do
  let(:team) { create(:team) }
  let(:user) { create(:user, github_installation_id: 42) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let(:parent) do
    create(:app_record, team: team, git_provider: "github",
           git_repo_full_name: "octo/repo", github_repo_full_name: "octo/repo")
  end
  let(:preview) { create(:app_record, :preview, parent_app: parent, pr_number: 7, team: team) }
  let(:github) { instance_double(GithubApp) }
  let(:octokit) { double("octokit") }

  before do
    allow(GithubApp).to receive(:new).with(42).and_return(github)
    allow(github).to receive(:client).and_return(octokit)
  end

  describe "#deployed!" do
    it "creates a new comment when none stored, saves comment id" do
      expect(octokit).to receive(:add_comment)
        .with("octo/repo", 7, /Preview deployed/)
        .and_return(double(id: 999))
      described_class.new(preview).deployed!(url: "https://x.wokku.cloud", commit_sha: "abc123")
      expect(preview.reload.preview_comment_id).to eq(999)
    end

    it "updates existing comment when comment id stored" do
      preview.update!(preview_comment_id: 999)
      expect(octokit).to receive(:update_comment)
        .with("octo/repo", 999, /Preview deployed/)
      described_class.new(preview).deployed!(url: "https://x.wokku.cloud", commit_sha: "abc123")
    end

    it "swallows API errors and logs" do
      expect(octokit).to receive(:add_comment).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:warn).with(/Commenter/)
      expect { described_class.new(preview).deployed!(url: "https://x", commit_sha: "abc") }.not_to raise_error
    end

    it "no-ops when no team user has a github_installation_id" do
      user.update!(github_installation_id: nil)
      expect(octokit).not_to receive(:add_comment)
      described_class.new(preview).deployed!(url: "https://x", commit_sha: "abc")
    end
  end

  describe ".cap_reached!" do
    it "posts a cap-reached comment without needing a preview record" do
      expect(octokit).to receive(:add_comment).with("octo/repo", 7, /cap reached/)
      described_class.cap_reached!(parent_app: parent, pr_number: 7)
    end

    it "no-ops when no team user has a github_installation_id" do
      user.update!(github_installation_id: nil)
      expect(octokit).not_to receive(:add_comment)
      described_class.cap_reached!(parent_app: parent, pr_number: 7)
    end

    it "swallows API errors and logs" do
      expect(octokit).to receive(:add_comment).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:warn).with(/cap_reached/)
      expect { described_class.cap_reached!(parent_app: parent, pr_number: 7) }.not_to raise_error
    end
  end
end
