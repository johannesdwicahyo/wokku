require "rails_helper"

RSpec.describe RestoreJob, type: :job do
  let(:user) { create(:user) }
  let(:team) { create(:team, owner: user) }
  let(:app) { create(:app_record, team: team, creator: user) }
  let(:db) { create(:database_service) }
  let(:backup) { create(:backup, database_service: db) }

  before { create(:app_database, app_record: app, database_service: db, alias_name: "DATABASE") }

  it "restores and logs database.restored to the team's activity" do
    allow(RestoreService).to receive(:new).with(backup).and_return(instance_double(RestoreService, perform!: true))
    expect { described_class.perform_now(backup.id, user.id) }.to change { Activity.where(action: "database.restored").count }.by(1)
    expect(Activity.last.team).to eq(team)
  end

  it "logs database.restore_failed with the error instead of raising" do
    allow(RestoreService).to receive(:new).and_return(instance_double(RestoreService).tap { |r| allow(r).to receive(:perform!).and_raise("PGPASSWORD=hunter2 failed") })
    expect { described_class.perform_now(backup.id, user.id) }.not_to raise_error
    failed = Activity.find_by(action: "database.restore_failed")
    expect(failed.metadata["error"]).to match(/did not complete/)
    expect(failed.metadata.to_s).not_to include("hunter2")
  end
end
