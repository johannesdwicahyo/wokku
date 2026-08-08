require "rails_helper"

RSpec.describe Preview::DnsRegistrar do
  let(:parent) { create(:app_record, name: "myapp") }
  let(:preview) { create(:app_record, :preview, parent_app: parent, pr_number: 7, team: parent.team) }
  let(:dns_client) { Wokku.config.dns_provider }

  describe "#register" do
    it "creates Cloudflare A record and stores PreviewDnsRecord" do
      expect(dns_client).to receive(:create_app_record)
        .with("myapp-pr-7", preview.server.host)
        .and_return("myapp-pr-7.wokku.cloud")
      expect { described_class.new(preview).register }
        .to change(PreviewDnsRecord, :count).by(1)
      record = PreviewDnsRecord.last
      expect(record.hostname).to eq("myapp-pr-7.wokku.cloud")
      expect(record.app_record_id).to eq(preview.id)
    end

    it "is idempotent — does not create a duplicate PreviewDnsRecord on retry" do
      PreviewDnsRecord.create!(app_record: preview, hostname: "myapp-pr-7.wokku.cloud")
      expect(dns_client).to receive(:create_app_record).with("myapp-pr-7", preview.server.host)
      expect { described_class.new(preview).register }.not_to change(PreviewDnsRecord, :count)
    end
  end

  describe "#unregister" do
    it "deletes Cloudflare record and PreviewDnsRecord when both exist" do
      PreviewDnsRecord.create!(app_record: preview, hostname: "myapp-pr-7.wokku.cloud")
      expect(dns_client).to receive(:delete_app_record).with("myapp-pr-7")
      expect { described_class.new(preview).unregister }
        .to change(PreviewDnsRecord, :count).by(-1)
    end

    it "is a no-op when no PreviewDnsRecord exists" do
      expect(dns_client).not_to receive(:delete_app_record)
      expect { described_class.new(preview).unregister }.not_to raise_error
    end

    it "swallows Cloudflare errors but still removes the local record" do
      PreviewDnsRecord.create!(app_record: preview, hostname: "myapp-pr-7.wokku.cloud")
      allow(dns_client).to receive(:delete_app_record).and_raise(Wokku::Providers::DnsError, "boom")
      expect { described_class.new(preview).unregister }
        .to change(PreviewDnsRecord, :count).by(-1)
    end
  end

  # WOKKU_APP_ENABLED cutover: which zone(s) register/unregister actually hit
  # is Wokku.config.dns_provider's job now (see
  # spec/services/cloudflare/dns_provider_spec.rb). DnsRegistrar's own
  # contract — register creates, unregister deletes, with the right name/host
  # — is covered by the #register/#unregister examples above.
end
