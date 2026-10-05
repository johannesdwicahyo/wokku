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

    # Regression: the create-app form ships an empty hidden input
    # (app_record[enabled_shared_engines][]="") so the array key is present
    # when no engine checkbox is ticked — it arrives as [""] and used to be
    # rejected as an unknown engine (HTTP 422). Blank entries must normalize
    # away, not error.
    it "normalizes the form's empty-hidden-input [\"\"] to [] and stays valid" do
      app.enabled_shared_engines = [""]
      expect(app.enabled_shared_engines).to eq([])
      expect(app).to be_valid
    end

    it "strips blank/whitespace entries but keeps real engines" do
      app.enabled_shared_engines = ["postgres", "", " ", "redis"]
      expect(app.enabled_shared_engines).to eq(%w[postgres redis])
      expect(app).to be_valid
    end

    it "can be created with no shared engine selected" do
      expect {
        create(:app_record, creator: user, server: server, enabled_shared_engines: [""])
      }.to change(AppRecord, :count).by(1)
    end

    it "rejects a retired engine newly added, but grandfathers one already stored" do
      app.enabled_shared_engines = %w[postgres rabbitmq]
      expect(app).not_to be_valid
      expect(app.errors[:enabled_shared_engines].join).to include("rabbitmq")

      app.save!(validate: false)
      app.reload.enabled_shared_engines = %w[postgres rabbitmq redis]
      expect(app).to be_valid
    end

    describe "#shared_engine_enabled?" do
      it "is true when the engine is in the array" do
        app.enabled_shared_engines = %w[postgres memcached]
        expect(app.shared_engine_enabled?("postgres")).to be true
        expect(app.shared_engine_enabled?(:memcached)).to be true
        expect(app.shared_engine_enabled?("redis")).to be false
      end
    end
  end
end
