require "test_helper"

class DeployTest < ActiveSupport::TestCase
  test "defaults to pending status" do
    deploy = Deploy.new(app_record: app_records(:one))
    assert_equal "pending", deploy.status
  end

  test "enum status values" do
    deploy = deploys(:one)
    assert deploy.pending?
    deploy.building!
    assert deploy.building?
  end

  test "duration returns difference between started_at and finished_at" do
    deploy = deploys(:one)
    assert_not_nil deploy.duration
    assert deploy.duration > 0
  end
end
