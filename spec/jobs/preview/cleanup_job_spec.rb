require "rails_helper"

RSpec.describe Preview::CleanupJob do
  it "calls Destroyer when preview exists" do
    parent = create(:app_record)
    preview = create(:app_record, :preview, parent_app: parent, pr_number: 7,
                     team: parent.team, server: parent.server)
    destroyer = instance_double(Preview::Destroyer, call: true)
    expect(Preview::Destroyer).to receive(:new).with(having_attributes(id: preview.id)).and_return(destroyer)
    described_class.new.perform(parent.id, 7)
  end

  it "no-ops when preview missing" do
    parent = create(:app_record)
    expect(Preview::Destroyer).not_to receive(:new)
    expect { described_class.new.perform(parent.id, 999) }.not_to raise_error
  end
end
