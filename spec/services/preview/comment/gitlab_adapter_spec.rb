require "rails_helper"

RSpec.describe Preview::Comment::GitlabAdapter do
  let(:team) { create(:team) }
  let(:user) { create(:user, gitlab_access_token: "fresh", gitlab_token_expires_at: 1.hour.from_now) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let(:parent) do
    create(:app_record, team: team, git_provider: "gitlab", git_repo_full_name: "octo/repo")
  end
  let(:preview) do
    create(:app_record, :preview, team: team, parent_app: parent, pr_number: 7, server: parent.server)
  end
  let(:gitlab_client) { instance_double(Gitlab::Client) }

  before { allow(Gitlab::Client).to receive(:new).with(user).and_return(gitlab_client) }

  describe "#add" do
    it "calls Gitlab::Client.add_comment and stores mr_iid on the preview" do
      expect(gitlab_client).to receive(:add_comment)
        .with("octo/repo", 7, "hello")
        .and_return(double(id: 999))

      result = described_class.new(parent, preview_app: preview).add(pr_number: 7, body: "hello")

      expect(result).to eq(999)
      expect(preview.reload.preview_comment_mr_iid).to eq(7)
    end

    it "returns nil if no team user has a gitlab token" do
      user.update!(gitlab_access_token: nil)
      result = described_class.new(parent, preview_app: preview).add(pr_number: 7, body: "hi")
      expect(result).to be_nil
    end
  end

  describe "#update" do
    it "calls Gitlab::Client.update_comment with stored mr_iid" do
      preview.update!(preview_comment_id: 999, preview_comment_mr_iid: 7)
      expect(gitlab_client).to receive(:update_comment)
        .with("octo/repo", 7, 999, "edited")

      described_class.new(parent, preview_app: preview).update(comment_id: 999, body: "edited")
    end

    it "no-ops when no mr_iid stored" do
      preview.update!(preview_comment_id: 999, preview_comment_mr_iid: nil)
      expect(gitlab_client).not_to receive(:update_comment)
      described_class.new(parent, preview_app: preview).update(comment_id: 999, body: "edited")
    end
  end
end
