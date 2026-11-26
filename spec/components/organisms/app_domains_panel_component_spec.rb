require "rails_helper"

RSpec.describe Organisms::AppDomainsPanelComponent, type: :component do
  let(:app) { create(:app_record, name: "shop") }

  it "tags HTTPS and puts the platform address last" do
    d = create(:domain, app_record: app, hostname: "shop.example.com", ssl_enabled: true)
    render_inline(described_class.new(app: app, domains: [ d ]))
    expect(page).to have_text("HTTPS")
    expect(page.all("a[href^='https://']").map(&:text)).to eq([ "shop.example.com", "shop.#{Wokku.config.canonical_domain}" ])
  end

  it "flags pending DNS" do
    d = create(:domain, app_record: app, hostname: "a.example.com", ssl_enabled: false, dns_verified: false)
    render_inline(described_class.new(app: app, domains: [ d ]))
    expect(page).to have_text("Pending DNS")
  end
end
