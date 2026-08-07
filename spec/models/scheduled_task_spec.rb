require "rails_helper"

RSpec.describe ScheduledTask do
  let(:app) { create(:app_record) }

  describe "validations" do
    it "requires a command" do
      task = ScheduledTask.new(app_record: app, schedule: "0 3 * * *")
      expect(task).not_to be_valid
      expect(task.errors[:command]).to include("can't be blank")
    end

    it "requires a schedule" do
      task = ScheduledTask.new(app_record: app, command: "echo hi")
      expect(task).not_to be_valid
      expect(task.errors[:schedule]).to include("can't be blank")
    end

    it "rejects invalid cron expressions" do
      task = ScheduledTask.new(app_record: app, command: "echo hi", schedule: "not a cron")
      expect(task).not_to be_valid
      expect(task.errors[:schedule].any? { |m| m.match?(/not a valid cron/) }).to be true
    end

    it "accepts standard cron expressions" do
      %w[
        0\ 3\ *\ *\ *
        */15\ *\ *\ *\ *
        0\ 0\ 1\ *\ *
        0\ 9-17\ *\ *\ 1-5
      ].each do |s|
        task = ScheduledTask.new(app_record: app, command: "echo hi", schedule: s.gsub("\\ ", " "))
        expect(task).to be_valid, "expected '#{s}' to be valid: #{task.errors.full_messages}"
      end
    end
  end

  describe "scopes" do
    it ".enabled returns only enabled tasks" do
      enabled  = create(:scheduled_task, app_record: app, enabled: true,  schedule: "0 1 * * *")
      disabled = create(:scheduled_task, app_record: app, enabled: false, schedule: "0 2 * * *")
      expect(ScheduledTask.enabled).to include(enabled)
      expect(ScheduledTask.enabled).not_to include(disabled)
    end

    it ".for_sync returns enabled tasks ordered deterministically" do
      a = create(:scheduled_task, app_record: app, schedule: "0 9 * * *", enabled: true)
      b = create(:scheduled_task, app_record: app, schedule: "0 3 * * *", enabled: true)
      create(:scheduled_task, app_record: app, schedule: "0 5 * * *", enabled: false)
      expect(ScheduledTask.for_sync.map(&:id)).to eq([ b.id, a.id ])
    end
  end
end
