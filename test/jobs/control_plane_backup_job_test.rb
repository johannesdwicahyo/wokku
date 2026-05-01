require "test_helper"

class ControlPlaneBackupJobTest < ActiveJob::TestCase
  test "no-ops with a warning when required env is not set" do
    ControlPlaneBackupJob::REQUIRED_ENV.each { |k| ENV.delete(k) }
    assert_nothing_raised do
      ControlPlaneBackupJob.new.perform
    end
  end
end
