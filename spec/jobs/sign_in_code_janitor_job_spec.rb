# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCodeJanitorJob, type: :job do
  it "deletes codes older than a day" do
    make = ->(at) { SignInCode.create!(email: "a@b.co", code_digest: "x", expires_at: at + 10.minutes, created_at: at) }
    old = make.(25.hours.ago)
    fresh = make.(23.hours.ago)
    described_class.perform_now
    expect(SignInCode.where(id: [ old.id, fresh.id ]).pluck(:id)).to eq([ fresh.id ])
  end
end
