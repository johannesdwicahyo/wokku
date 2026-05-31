require "rails_helper"

RSpec.describe KnownDevice do
  describe ".fingerprint" do
    it "is stable and distinct" do
      ua1 = "Mozilla/5.0 (Macintosh) Chrome/120"
      ua2 = "Mozilla/5.0 (Linux; Android 14) Firefox/121"
      expect(KnownDevice.fingerprint(ua1)).to eq(KnownDevice.fingerprint(ua1))
      expect(KnownDevice.fingerprint(ua1)).not_to eq(KnownDevice.fingerprint(ua2))
      expect(KnownDevice.fingerprint(ua1).length).to eq(64)
    end
  end

  describe ".summarise" do
    it "returns human-readable browser + OS" do
      expect(KnownDevice.summarise("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120")).to eq("Chrome on macOS")
      expect(KnownDevice.summarise("Mozilla/5.0 (Linux; Android 14) Firefox/121")).to eq("Firefox on Android")
      expect(KnownDevice.summarise("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605.1")).to eq("Safari on iOS")
      expect(KnownDevice.summarise("")).to eq("unknown browser")
      expect(KnownDevice.summarise(nil)).to eq("unknown browser")
    end
  end
end
