require "rails_helper"

RSpec.describe Apps::Cron::TaskCreator do
  let(:app) { app_records(:one) }

  describe "#call!" do
    it "creates a ScheduledTask without any dokku crontab sync" do
      expect(Hosts::Ssh).not_to receive(:new)
      result = nil
      expect {
        result = described_class.new(app).call!(command: "bin/rails runner Foo.bar", schedule: "*/5 * * * *", description: "Tick")
      }.to change(ScheduledTask, :count).by(1)
      expect(result).to be_a(ScheduledTask)
      expect(result.command).to eq("bin/rails runner Foo.bar")
      expect(result.schedule).to eq("*/5 * * * *")
      expect(result.description).to eq("Tick")
    end

    it "raises Apps::Cron::Error on validation failure (blank schedule) and does not create a row" do
      expect {
        expect {
          described_class.new(app).call!(command: "anything", schedule: "", description: nil)
        }.to raise_error(Apps::Cron::Error, /can't be blank|invalid/i)
      }.not_to change(ScheduledTask, :count)
    end
  end
end
