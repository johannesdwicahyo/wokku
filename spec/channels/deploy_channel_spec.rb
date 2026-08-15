require "rails_helper"

RSpec.describe DeployChannel do
  let(:team)   { create(:team) }
  let(:app)    { create(:app_record, team: team) }
  let(:deploy) { create(:deploy, app_record: app) }

  it "confirms a member of the team that owns the deploy's app" do
    member = create(:user)
    create(:team_membership, team: team, user: member)
    stub_connection current_user: member

    subscribe(deploy_id: deploy.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(deploy)
  end

  it "rejects a user who is not a member of the app's team (IDOR guard)" do
    outsider = create(:user)
    stub_connection current_user: outsider

    subscribe(deploy_id: deploy.id)

    expect(subscription).to be_rejected
  end

  it "rejects an unauthenticated connection" do
    stub_connection current_user: nil

    subscribe(deploy_id: deploy.id)

    expect(subscription).to be_rejected
  end

  it "confirms an admin regardless of team membership" do
    admin = users(:admin)
    stub_connection current_user: admin

    subscribe(deploy_id: deploy.id)

    expect(subscription).to be_confirmed
  end
end
