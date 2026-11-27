require "rails_helper"

RSpec.describe Organisms::AppSecurityPanelComponent, type: :component do
  let(:app) { create(:app_record) }
  let(:base) { { app_record: app, server: app.server, image_ref: "127.0.0.1:5000/x:1" } }

  def text_for(scan, locale = :en)
    I18n.with_locale(locale) { render_inline(described_class.new(app: app, scan: scan)) }
    page.text.squish
  end

  it "shows the first-scan copy with no scan (en/id)" do
    expect(text_for(nil)).to include("First scan after the next deploy")
    expect(text_for(nil, :id)).to include("Pemindaian pertama setelah deploy berikutnya")
  end

  it "shows Scanning… for pending and claimed" do
    expect(text_for(ImageScan.new(base.merge(status: :pending)))).to include("Scanning…")
    expect(text_for(ImageScan.new(base.merge(status: :claimed)))).to include("Scanning…")
  end

  it "shows the failure copy" do
    expect(text_for(ImageScan.new(base.merge(status: :failed)))).to include("Scan failed · retry tonight")
    expect(text_for(ImageScan.new(base.merge(status: :failed)), :id)).to include("Pemindaian gagal")
  end

  it "shows counts, fixable, version and the findings link when succeeded" do
    scan = ImageScan.new(base.merge(status: :succeeded, scanner_version: "0.58.1", updated_at: 2.hours.ago,
                                    counts: { "critical" => 0, "high" => 2, "fixable" => 1 }))
    t = text_for(scan)
    expect(t).to include("2 High", "1 fixable", "Trivy 0.58.1")
    expect(page).to have_link("View findings")
    expect(text_for(scan, :id)).to include("1 bisa diperbaiki")
  end

  it "reads zero findings without ever saying secure" do
    scan = ImageScan.new(base.merge(status: :succeeded, counts: {}, updated_at: 1.hour.ago))
    expect(text_for(scan)).to include("No known vulnerabilities in the image")
    expect(text_for(scan, :id)).to include("Tidak ada kerentanan yang diketahui di image")
    expect(text_for(scan, :id).downcase).not_to match(/secure|aman/)
    expect(text_for(scan).downcase).not_to include("secure")
  end
end
