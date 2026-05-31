# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardDeleteAccountJob, type: :job do
  let(:user) do
    u = User.create!(email: "todelete-#{SecureRandom.hex(4)}@example.com",
                     password: "password123456",
                     deletion_scheduled_at: 1.day.ago)
    team = Team.create!(name: "Delete Test Team", owner: u)
    TeamMembership.create!(user: u, team: team, role: "admin")
    u
  end

  it "no-ops if user has already been hard-deleted" do
    original_deleted_at = 1.hour.ago
    user.update_columns(deleted_at: original_deleted_at)
    expect { described_class.perform_now(user.id) }.not_to raise_error
    expect(user.reload.deleted_at.to_i).to be_within(2).of(original_deleted_at.to_i)
  end

  it "no-ops if user not found" do
    expect { described_class.perform_now("00000000-0000-0000-0000-000000000000") }.not_to raise_error
  end

  it "nulls PII columns on user" do
    described_class.perform_now(user.id)
    user.reload
    expect(user.deleted?).to be_truthy
    expect(user.email).to match(/^deleted-/)
    expect(user.encrypted_password).to eq("")
    expect(user.name).to be_nil
    expect(user.avatar_url).to be_nil
    expect(user.provider).to be_nil
    expect(user.uid).to be_nil
  end

  # "preserves DepositTransaction rows" removed in 1.8 — the table is gone.

  it "hard delete is idempotent (second call is safe)" do
    described_class.perform_now(user.id)
    expect { described_class.perform_now(user.id) }.not_to raise_error
  end
end
