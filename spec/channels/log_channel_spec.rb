require "rails_helper"

RSpec.describe LogChannel, type: :channel do
  it "raises when subscribing without app_id" do
    stub_connection current_user: users(:one)
    expect { subscribe }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "raises when subscribing with a nonexistent app_id" do
    stub_connection current_user: users(:one)
    expect { subscribe(app_id: -999) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "subscribes and streams for a valid app" do
    stub_connection current_user: users(:one)
    app = app_records(:one)
    subscribe(app_id: app.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(app)
  end

  it "rejects a user who is not a member of the app's team (IDOR guard)" do
    stub_connection current_user: users(:one)
    subscribe(app_id: app_records(:two).id)
    expect(subscription).to be_rejected
  end

  it "rejects an unauthenticated connection" do
    stub_connection current_user: nil
    subscribe(app_id: app_records(:one).id)
    expect(subscription).to be_rejected
  end

  it "confirms an admin regardless of team membership" do
    stub_connection current_user: users(:admin)
    subscribe(app_id: app_records(:two).id)
    expect(subscription).to be_confirmed
  end
end
