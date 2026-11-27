# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageScan do
  let(:app_record) { create(:app_record) }

  def scan(status) = described_class.create!(app_record: app_record, server: app_record.server, image_ref: "r/x:1", status: status)

  it "allows only one pending-or-claimed scan per app" do
    scan(:pending)
    expect { scan(:claimed) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows many terminal scans" do
    scan(:succeeded)
    expect { scan(:failed) }.not_to raise_error
  end
end
