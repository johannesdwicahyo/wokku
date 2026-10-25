require "rails_helper"
require "rake"

RSpec.describe "mobile rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("mobile:ui_fixture")
  end

  def run(name, *args)
    Rake::Task[name].reenable
    expect { Rake::Task[name].invoke(*args) }.to output(/email=\S+ password=\S+/).to_stdout
  end

  it "ui_fixture builds one app per status, deploys, releases, incidents and a mute — idempotently" do
    2.times { run("mobile:ui_fixture") }
    user = User.find_by!(email: "ios-ui@wokku.test")
    apps = AppRecord.where(team: user.teams)
    expect(apps.pluck(:status).map(&:to_s)).to match_array(%w[running crashed deploying sleeping stopped created])
    expect(Deploy.where(app_record: apps).count).to eq(3)
    expect(Release.where(app_record: apps).count).to eq(3)
    expect(Incident.where(app_record: apps).where(resolved_at: nil).count).to eq(1)
    expect(Incident.where(app_record: apps).where.not(resolved_at: nil).count).to eq(1)
    expect(AlertMute.where(user: user).count).to eq(1)
  end

  it "ui_fixture refuses to run in production" do
    allow(Rails.env).to receive(:production?).and_return(true)
    Rake::Task["mobile:ui_fixture"].reenable
    expect { Rake::Task["mobile:ui_fixture"].invoke }.to raise_error(/production/)
  end

  it "app_review_account adds a member to the given team and rotates its password" do
    team = create(:team)
    run("mobile:app_review_account", team.id)
    user = User.find_by!(email: "appreview@wokku.cloud")
    expect(TeamMembership.find_by(user: user, team: team).role).to eq("member")
    first = user.encrypted_password
    run("mobile:app_review_account", team.id)
    expect(user.reload.encrypted_password).not_to eq(first)
    expect(TeamMembership.where(user: user, team: team).count).to eq(1)
  end

  describe "app_review_account takeover guard" do
    def refuses(user, team)
      before = user.encrypted_password
      Rake::Task["mobile:app_review_account"].reenable
      expect { Rake::Task["mobile:app_review_account"].invoke(team.id) }
        .to raise_error(SystemExit).and output(/refusing to take it over/).to_stderr
      expect(user.reload.encrypted_password).to eq(before)
    end

    it "refuses an existing admin with that email" do
      user = create(:user, email: "appreview@wokku.cloud")
      user.update_column(:role, 1)
      refuses(user, create(:team))
    end

    it "refuses an existing user who belongs to another team" do
      user = create(:user, email: "appreview@wokku.cloud")
      TeamMembership.create!(user: user, team: create(:team), role: :member)
      refuses(user, create(:team))
    end
  end
end
