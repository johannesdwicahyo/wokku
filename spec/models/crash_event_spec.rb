require "rails_helper"

RSpec.describe CrashEvent do
  it "belongs to an app and exposes the crash details" do
    app = create(:app_record)
    ev = app.crash_events.create!(container_id: "demo.web.1.x", exit_code: 137, oom_killed: true,
                                  exited_at: Time.current, log_excerpt: "killed")
    expect(ev.app_record).to eq(app)
    expect(app.crash_events.recent.first).to eq(ev)
  end

  it "enforces one event per container_id (dedupe)" do
    app = create(:app_record)
    app.crash_events.create!(container_id: "dup", exit_code: 1, exited_at: Time.current)
    expect {
      app.crash_events.create!(container_id: "dup", exit_code: 1, exited_at: Time.current)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
