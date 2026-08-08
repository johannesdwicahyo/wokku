require "rails_helper"

# W7 Phase 3: the deploy lock is control-plane state
# (app_records.deploy_locked_at) — no dokku involved.
RSpec.describe Apps::Lifecycle::DeployLock do
  let(:app) { app_records(:one) }

  describe "#lock!" do
    it "stamps deploy_locked_at and returns true" do
      expect(described_class.new(app).lock!).to be true
      expect(app.reload.deploy_locked_at).to be_present
    end

    it "is a no-op when already locked (timestamp unchanged)" do
      app.update!(deploy_locked_at: 2.hours.ago)
      expect { described_class.new(app).lock! }
        .not_to change { app.reload.deploy_locked_at }
    end
  end

  describe "#unlock!" do
    it "clears deploy_locked_at and returns false" do
      app.update!(deploy_locked_at: Time.current)
      expect(described_class.new(app).unlock!).to be false
      expect(app.reload.deploy_locked_at).to be_nil
    end

    it "is a no-op when already unlocked" do
      expect(described_class.new(app).unlock!).to be false
    end
  end

  describe "#locked?" do
    it "is true when deploy_locked_at is set" do
      app.update!(deploy_locked_at: Time.current)
      expect(described_class.new(app).locked?).to be true
    end

    it "is false when deploy_locked_at is nil" do
      expect(described_class.new(app).locked?).to be false
    end
  end
end
