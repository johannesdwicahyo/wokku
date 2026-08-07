require "rails_helper"

# Bundle v2 REVISED 2026-05-31 — box_size + enabled_shared_engines columns
# on AppRecord. See memory/project_bundle_v2_locked_spec.md.
RSpec.describe AppRecord, "bundle v2 box model" do
  let(:user)   { create(:user) }
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, creator: user, server: server) }

  describe "box_size" do
    it "accepts every BOX_SIZES value" do
      AppRecord::BOX_SIZES.each do |size|
        app.box_size = size
        expect(app).to be_valid, "expected #{size} to be valid"
      end
    end

    it "allows nil (legacy rows)" do
      app.box_size = nil
      expect(app).to be_valid
    end

    it "rejects unknown sizes" do
      app.box_size = "jumbo"
      expect(app).not_to be_valid
      expect(app.errors[:box_size]).to be_present
    end
  end

  describe "enabled_shared_engines" do
    it "defaults to empty array" do
      expect(app.enabled_shared_engines).to eq([])
    end

    it "accepts any subset of SHARED_ENGINES" do
      app.enabled_shared_engines = %w[postgres redis]
      expect(app).to be_valid
      app.enabled_shared_engines = AppRecord::SHARED_ENGINES
      expect(app).to be_valid
    end

    it "rejects unknown engines" do
      app.enabled_shared_engines = %w[postgres riak]
      expect(app).not_to be_valid
      expect(app.errors[:enabled_shared_engines].first).to include("riak")
    end

    describe "#shared_engine_enabled?" do
      it "is true when the engine is in the array" do
        app.enabled_shared_engines = %w[postgres meilisearch]
        expect(app.shared_engine_enabled?("postgres")).to be true
        expect(app.shared_engine_enabled?(:meilisearch)).to be true
        expect(app.shared_engine_enabled?("redis")).to be false
      end
    end
  end
end
