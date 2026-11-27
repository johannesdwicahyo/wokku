# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageScan do
  let(:app_record) { create(:app_record) }

  def scan(status) = described_class.create!(app_record: app_record, server: app_record.server, image_ref: "r/x:1", status: status)

  it "allows only one pending scan per app, alongside a claimed one" do
    scan(:claimed)
    scan(:pending)
    expect { scan(:pending) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "has no server_id index beside (server_id, status)" do
    names = described_class.connection.indexes(:image_scans).map(&:name)
    expect(names).to include("index_image_scans_on_server_id_and_status")
    expect(names).not_to include("index_image_scans_on_server_id")
  end

  it "allows many terminal scans" do
    scan(:succeeded)
    expect { scan(:failed) }.not_to raise_error
  end

  describe ".for_image" do
    # ids are random uuid v4: id order is not age order.
    def at(status, age, id) = described_class.create!(id: id, app_record: app_record, server: app_record.server,
                                                      image_ref: "r/x:1", status: status, created_at: age.ago)

    it "returns the newer of two succeeded scans whatever their ids" do
      at(:succeeded, 2.hours, "ffffffff-0000-4000-8000-000000000000")
      newer = at(:succeeded, 1.hour, "00000000-0000-4000-8000-000000000000")
      expect(described_class.for_image(app_record, "r/x:1").id).to eq(newer.id)
    end

    it "shows a newer pending scan (Scanning…) over an older failed one" do
      at(:failed, 2.hours, "ffffffff-0000-4000-8000-000000000000")
      pending = at(:pending, 1.hour, "00000000-0000-4000-8000-000000000000")
      expect(described_class.for_image(app_record, "r/x:1")).to have_attributes(id: pending.id, status: "pending")
    end
  end
end
