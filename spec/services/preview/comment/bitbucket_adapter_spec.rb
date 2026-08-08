require "rails_helper"

RSpec.describe Preview::Comment::BitbucketAdapter do
  let(:team) { create(:team) }
  let(:user) { create(:user, bitbucket_access_token: "fresh", bitbucket_token_expires_at: 1.hour.from_now) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let(:parent) do
    create(:app_record, team: team, git_provider: "bitbucket", git_repo_full_name: "octo/repo")
  end
  let(:preview) do
    create(:app_record, :preview, team: team, parent_app: parent, pr_number: 7, server: parent.server)
  end
  let(:bb_client) { instance_double(Bitbucket::Client) }

  before { allow(Bitbucket::Client).to receive(:new).with(user).and_return(bb_client) }

  describe "#add" do
    it "calls Bitbucket::Client.add_comment and stores pr_iid on the preview" do
      expect(bb_client).to receive(:add_comment)
        .with("octo/repo", 7, "hello")
        .and_return(double(id: 999))

      result = described_class.new(parent, preview_app: preview).add(pr_number: 7, body: "hello")

      expect(result).to eq(999)
      expect(preview.reload.preview_comment_mr_iid).to eq(7)
    end

    it "returns nil if no team user has a bitbucket token" do
      user.update!(bitbucket_access_token: nil)
      result = described_class.new(parent, preview_app: preview).add(pr_number: 7, body: "hi")
      expect(result).to be_nil
    end
  end

  describe "#update" do
    it "calls Bitbucket::Client.update_comment with stored pr_iid" do
      preview.update!(preview_comment_id: 999, preview_comment_mr_iid: 7)
      expect(bb_client).to receive(:update_comment)
        .with("octo/repo", 7, 999, "edited")

      described_class.new(parent, preview_app: preview).update(comment_id: 999, body: "edited")
    end

    it "no-ops when no pr_iid stored" do
      preview.update!(preview_comment_id: 999, preview_comment_mr_iid: nil)
      expect(bb_client).not_to receive(:update_comment)
      described_class.new(parent, preview_app: preview).update(comment_id: 999, body: "edited")
    end
  end
end
