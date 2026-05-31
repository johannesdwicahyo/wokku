require "rails_helper"

RSpec.describe Activity do
  describe ".log" do
    it "creates an activity record" do
      user = users(:one)
      team = teams(:one)
      expect {
        Activity.log(user: user, team: team, action: "app.created", metadata: { name: "test-app" })
      }.to change { Activity.count }.by(1)
    end
  end

  describe "#description" do
    it "returns the human-readable action" do
      activity = Activity.new(action: "app.deployed")
      expect(activity.description).to eq("deployed")
    end
  end
end
