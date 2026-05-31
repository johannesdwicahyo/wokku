# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrPreviewCleanupJob, type: :job do
  it "no-ops when preview missing" do
    parent = create(:app_record)
    expect(Preview::Destroyer).not_to receive(:new)
    described_class.new.perform(parent_app_id: parent.id, pr_number: 999)
  end
end
