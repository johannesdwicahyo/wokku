# frozen_string_literal: true

require "rails_helper"

# 2026-11-22: one person came back three times (josganuye@, alexpoas6@,
# ekuzikaa8@) deploying xray from the same GitHub owner. Suspending a user now
# remembers the GitHub owners behind their repos, and a later app from those
# owners that also looks like a relay is ban evasion.
RSpec.describe "relay ban evasion" do
  describe "AppRecord#repo_owner" do
    {
      "owner/repo" => "owner",
      "Josganuye-Netizen/xray-canndy-" => "josganuye-netizen",
      "https://github.com/josganuye-netizen/xray-payload.enhacd" => "josganuye-netizen",
      "https://gitlab.com/Some.One/app.git" => "some.one",
      "git@github.com:owner/repo.git" => "owner",
      "" => nil,
      "not a repo" => nil
    }.each do |ref, owner|
      it "reads #{owner.inspect} from #{ref.inspect}" do
        expect(build(:app_record, git_repository_url: ref).repo_owner).to eq(owner)
      end
    end

    it "prefers the connected repo name over the URL" do
      app = build(:app_record, git_repo_full_name: "real/one", git_repository_url: "https://github.com/other/two")
      expect(app.repo_owner).to eq("real")
    end
  end

  describe "User#suspend_for_abuse!" do
    let(:user) { create(:user, github_username: "Evader") }
    let(:team) { create(:team, owner: user) }

    before { allow(Lifecycle::Ops).to receive(:converge!) }

    it "remembers the GitHub owners behind the user's apps and their own login" do
      create(:app_record, team: team, git_repo_full_name: "relay-org/xray-thing", status: :stopped)
      user.suspend_for_abuse!
      expect(user.reload.abuse_repo_owners).to contain_exactly("relay-org", "evader")
      expect(User.banned_repo_owner?("relay-org")).to be(true)
      expect(User.banned_repo_owner?("someone-else")).to be(false)
    end

    it "no longer counts an owner once the suspension is lifted" do
      create(:app_record, team: team, git_repo_full_name: "relay-org/x", status: :stopped)
      user.suspend_for_abuse!
      user.update!(abuse_suspended_at: nil)
      expect(User.banned_repo_owner?("relay-org")).to be(false)
    end
  end
end
