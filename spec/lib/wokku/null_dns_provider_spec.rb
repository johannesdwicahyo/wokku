require "rails_helper"

RSpec.describe Wokku::Providers::NullDnsProvider do
  subject(:provider) { described_class.new }

  it "no-ops create_app_record and logs a manual-DNS hint" do
    expect(Rails.logger).to receive(:info).with(/manual DNS.*my-app.*1\.2\.3\.4/i)
    expect(provider.create_app_record("my-app", "1.2.3.4")).to be_nil
  end

  it "no-ops delete_app_record without raising" do
    expect { provider.delete_app_record("my-app") }.not_to raise_error
  end

  it "no-ops set_proxied! without raising" do
    expect { provider.set_proxied!("my-app", proxied: true) }.not_to raise_error
  end

  it "is the default dns_provider when none is injected" do
    saved = Wokku.instance_variable_get(:@config)
    Wokku.instance_variable_set(:@config, nil)
    expect(Wokku.config.dns_provider).to be_a(described_class)
  ensure
    Wokku.instance_variable_set(:@config, saved)
  end
end
