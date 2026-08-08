require "rails_helper"

RSpec.describe Apps::Cron::TaskDestroyer do
  let(:app)  { app_records(:one) }
  let(:task) { app.scheduled_tasks.create!(command: "bin/rails ...", schedule: "*/5 * * * *") }

  describe "#call!" do
    it "destroys the task without any dokku crontab sync" do
      task # ensure created
      expect(Hosts::Ssh).not_to receive(:new)
      expect { described_class.new(app).call!(task) }.to change(ScheduledTask, :count).by(-1)
    end
  end
end
