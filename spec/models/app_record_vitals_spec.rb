require "rails_helper"

RSpec.describe AppRecord, "vitals token" do
  let(:app) { app_records(:one) }

  describe "#ensure_vitals_ingest_token!" do
    it "generates a token if missing" do
      app.update!(vitals_ingest_token: nil)
      expect { app.ensure_vitals_ingest_token! }
        .to change { app.reload.vitals_ingest_token }.from(nil)
      expect(app.vitals_ingest_token.length).to be >= 24
    end

    it "is idempotent when a token already exists" do
      app.ensure_vitals_ingest_token!
      token = app.reload.vitals_ingest_token
      app.ensure_vitals_ingest_token!
      expect(app.reload.vitals_ingest_token).to eq(token)
    end
  end

  describe "#rotate_vitals_ingest_token!" do
    it "replaces the token with a new one" do
      app.ensure_vitals_ingest_token!
      old = app.reload.vitals_ingest_token
      app.rotate_vitals_ingest_token!
      expect(app.reload.vitals_ingest_token).not_to eq(old)
    end
  end
end
