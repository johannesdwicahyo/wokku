require "rails_helper"

RSpec.describe Preview::Comment::Dispatcher do
  let(:team) { create(:team) }
  let(:user) { create(:user, github_installation_id: 42) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let(:parent) do
    create(:app_record, team: team, github_repo_full_name: "octo/repo") # what GitHub connect sets
  end

  describe ".for" do
    it "returns the github adapter for a github-connected parent" do
      adapter = described_class.for(parent)
      expect(adapter).to be_a(Preview::Comment::GithubAdapter)
    end

    it "returns nil for a parent with no provider" do
      parent.update_columns(git_provider: nil, github_repo_full_name: nil, git_repo_full_name: nil)
      expect(described_class.for(parent)).to be_nil
    end

    it "returns the gitlab adapter for a gitlab-connected parent" do
      gitlab_parent = create(:app_record, team: team,
                              git_provider: "gitlab",
                              git_repo_full_name: "octo/repo")
      adapter = described_class.for(gitlab_parent)
      expect(adapter).to be_a(Preview::Comment::GitlabAdapter)
    end

    it "returns the bitbucket adapter for a bitbucket-connected parent" do
      bb_parent = create(:app_record, team: team,
                          git_provider: "bitbucket",
                          git_repo_full_name: "octo/repo")
      adapter = described_class.for(bb_parent)
      expect(adapter).to be_a(Preview::Comment::BitbucketAdapter)
    end

    it "raises for an unsupported provider" do
      parent.update_column(:git_provider, "fossil")
      expect { described_class.for(parent) }.to raise_error(/unsupported/i)
    end
  end
end
