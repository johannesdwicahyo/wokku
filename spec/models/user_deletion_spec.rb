# frozen_string_literal: true

require "rails_helper"

# Demonstration spec for the strangler-fig RSpec + FactoryBot migration.
# Mirrors the (now-removed) test/models/user_deletion_test.rb. Showcases:
#   - FactoryBot traits (:pending_deletion, :hard_deleted) replacing
#     fixture + update_columns + manual reset boilerplate.
#   - RSpec describe/context/it grouping vs flat Minitest tests.
#   - `let` for shared subject without instance-variable plumbing.
RSpec.describe User, type: :model do
  describe "scopes" do
    describe ".active" do
      it "excludes hard-deleted users" do
        deleted = create(:user, :hard_deleted)
        expect(User.active).not_to include(deleted)
      end

      it "includes non-deleted users" do
        live = create(:user)
        expect(User.active).to include(live)
      end
    end

    describe ".pending_deletion" do
      it "finds scheduled-but-not-deleted users" do
        scheduled = create(:user, :pending_deletion)
        expect(User.pending_deletion).to include(scheduled)
      end

      it "excludes already hard-deleted users" do
        already_dead = create(:user,
                              deletion_scheduled_at: 1.day.ago,
                              deleted_at: Time.current)
        expect(User.pending_deletion).not_to include(already_dead)
      end
    end

    describe ".ready_for_hard_delete" do
      it "includes past-due scheduled users" do
        past_due = create(:user, deletion_scheduled_at: 1.second.ago)
        expect(User.ready_for_hard_delete).to include(past_due)
      end

      it "excludes future-scheduled users" do
        future = create(:user, deletion_scheduled_at: 1.day.from_now)
        expect(User.ready_for_hard_delete).not_to include(future)
      end
    end
  end

  describe "predicates" do
    describe "#deleted?" do
      it "returns false when deleted_at is nil" do
        expect(create(:user).deleted?).to be(false)
      end

      it "returns true when deleted_at is set" do
        expect(create(:user, :hard_deleted).deleted?).to be(true)
      end
    end

    describe "#deletion_pending?" do
      it "is true when scheduled and not yet deleted" do
        expect(create(:user, :pending_deletion).deletion_pending?).to be(true)
      end

      it "is false when already hard-deleted" do
        user = create(:user, deletion_scheduled_at: 1.day.ago, deleted_at: Time.current)
        expect(user.deletion_pending?).to be(false)
      end

      it "is false when not scheduled" do
        expect(create(:user).deletion_pending?).to be(false)
      end
    end
  end

  describe "#schedule_deletion!" do
    let(:user) { create(:user) }

    it "sets deletion_scheduled_at to 3 days from now" do
      freeze_time do
        user.schedule_deletion!
        expect(user.reload.deletion_scheduled_at).to be_within(5.seconds).of(3.days.from_now)
      end
    end

    it "is idempotent when already pending" do
      original = 2.days.from_now
      user.update!(deletion_scheduled_at: original)
      user.schedule_deletion!
      expect(user.reload.deletion_scheduled_at).to be_within(5.seconds).of(original)
    end

    it "is idempotent when already hard-deleted" do
      user.update!(deleted_at: 1.hour.ago)
      user.schedule_deletion!
      expect(user.reload.deletion_scheduled_at).to be_nil
    end

    it "enqueues DokkuAppActionJob for each app the user owns" do
      # Falls back to fixtures for AppRecord since we don't have a factory yet
      # — the migration is gradual, not all-at-once.
      fixture_user = User.find(users(:one).id)
      app_records(:one) # ensure fixture loaded
      expect {
        fixture_user.schedule_deletion!
      }.to have_enqueued_job(DokkuAppActionJob).at_least(:once)
      fixture_user.update_columns(deletion_scheduled_at: nil)
    end
  end

  describe "#cancel_deletion!" do
    it "clears deletion_scheduled_at" do
      user = create(:user, :pending_deletion)
      user.cancel_deletion!
      expect(user.reload.deletion_scheduled_at).to be_nil
    end
  end

  describe "#active_for_authentication?" do
    it "returns true for a normal user" do
      expect(create(:user).active_for_authentication?).to be(true)
    end

    it "returns false for a hard-deleted user" do
      expect(create(:user, :hard_deleted).active_for_authentication?).to be(false)
    end

    it "returns true for a soft-deleted (pending) user — they can sign in to cancel" do
      expect(create(:user, :pending_deletion).active_for_authentication?).to be(true)
    end
  end

  describe "#inactive_message" do
    it "returns :account_deleted for a hard-deleted user" do
      expect(create(:user, :hard_deleted).inactive_message).to eq(:account_deleted)
    end
  end
end
