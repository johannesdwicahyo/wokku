require "rails_helper"

RSpec.describe Api::V1::Serializers::ScheduledTask do
  let(:app) { app_records(:one) }
  let(:task) do
    app.scheduled_tasks.create!(
      command: "bin/rails runner Foo.bar",
      schedule: "*/5 * * * *",
      description: "Ticker"
    )
  end

  it "serializes the public fields" do
    result = described_class.new(task).call
    expect(result).to eq(
      id: task.id,
      command: "bin/rails runner Foo.bar",
      schedule: "*/5 * * * *",
      description: "Ticker",
      enabled: true,
      created_at: task.created_at
    )
  end
end
