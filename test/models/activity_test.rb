require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "log creates activity record" do
    user = users(:one)
    team = teams(:one)

    assert_difference "Activity.count", 1 do
      Activity.log(user: user, team: team, action: "app.created", metadata: { name: "test-app" })
    end
  end

  test "description returns human-readable action" do
    activity = Activity.new(action: "app.deployed")
    assert_equal "deployed", activity.description
  end
end
