require "rails_helper"

RSpec.describe Molecules::CrashLoopBannerComponent, type: :component do
  it "renders a crash-loop notice for a crashed app" do
    app = build(:app_record, name: "loopy", status: :crashed)
    render_inline(described_class.new(app: app))
    expect(page).to have_text(/crash/i)
    expect(page).to have_text(/deploy a fix/i)
  end

  it "renders nothing for a running app" do
    app = build(:app_record, status: :running)
    render_inline(described_class.new(app: app))
    expect(page).not_to have_text(/crash/i)
  end
end
