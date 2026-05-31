# frozen_string_literal: true
require "rails_helper"

RSpec.describe Lead, type: :model do
  it "is valid with email + pain_text" do
    expect(build(:lead)).to be_valid
  end

  it "requires pain_text" do
    l = build(:lead, pain_text: nil)
    expect(l).not_to be_valid
    expect(l.errors[:pain_text]).to be_present
  end

  it "caps pain_text length at 5000" do
    l = build(:lead, pain_text: "x" * 5001)
    expect(l).not_to be_valid
  end

  it "validates email format when present" do
    expect(build(:lead, email: "not-an-email")).not_to be_valid
    expect(build(:lead, email: nil)).to be_valid # email is optional (WhatsApp-only path)
  end

  it "stores utm fields as plain strings" do
    l = create(:lead, utm_source: "meta", utm_campaign: "fvp-v1")
    expect(l.reload.utm_source).to eq("meta")
    expect(l.utm_campaign).to eq("fvp-v1")
  end
end
