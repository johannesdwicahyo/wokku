require "rails_helper"

RSpec.describe Apps::DeletionProgress do
  let(:app) { create(:app_record, name: "shop") }

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it "records steps, broadcasts each change, and is readable only by the app's team" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with(described_class.stream(app.id), hash_including(target: "app_deletion_#{app.id}")).exactly(3).times
    progress = described_class.start!(app)
    progress.step("Removing DNS records", :running)
    progress.step("Removing DNS records", :done)

    member = create(:user)
    create(:team_membership, team: app.team, user: member, role: :member)
    data = described_class.for(app.id, member)
    expect(data[:steps].map { |s| [ s[:label], s[:state] ] }).to eq([ [ "Queued", "done" ], [ "Removing DNS records", "done" ] ])
    expect(described_class.for(app.id, create(:user))).to be_nil
  end
end
