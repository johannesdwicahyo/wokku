require "rails_helper"

RSpec.describe Molecules::RecentCrashesComponent, type: :component do
  it "lists recent crashes with exit code and OOM" do
    app = create(:app_record)
    app.crash_events.create!(container_id: "c1", exit_code: 137, oom_killed: true, exited_at: 1.hour.ago, log_excerpt: "killed: too many connections")
    render_inline(described_class.new(app: app))
    expect(page).to have_text("137")
    expect(page).to have_text(/OOM/i)
    expect(page).to have_text(/too many connections/i)
  end

  it "renders nothing when there are no crashes" do
    render_inline(described_class.new(app: create(:app_record)))
    expect(page).not_to have_text(/crash/i)
  end
end
