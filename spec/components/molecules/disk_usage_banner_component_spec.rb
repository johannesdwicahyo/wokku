require "rails_helper"

RSpec.describe Molecules::DiskUsageBannerComponent, type: :component do
  let(:app) { create(:app_record, volume_disk_gb: 10) }

  it "renders nothing under 90%" do
    allow(app).to receive(:volume_used_gb).and_return(5.0)
    render_inline(described_class.new(record: app))
    expect(page.text).to be_blank
  end

  it "warns at 95%" do
    allow(app).to receive(:volume_used_gb).and_return(9.5)
    render_inline(described_class.new(record: app))
    expect(page).to have_text("Disk 95% full")
  end
end
