require "test_helper"

class NotifyJobTest < ActiveSupport::TestCase
  test "build_message formats deploy_succeeded" do
    job = NotifyJob.new
    deploy = Deploy.new(commit_sha: "abc1234567890")
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { OpenStruct.new(version: 3) }

    msg = job.send(:build_message, deploy, "deploy_succeeded")
    assert_includes msg, "my-app"
    assert_includes msg, "deployed successfully"
    assert_includes msg, "abc1234"
  end

  test "build_message formats deploy_failed" do
    job = NotifyJob.new
    deploy = Deploy.new
    deploy.define_singleton_method(:app_record) { OpenStruct.new(name: "my-app") }
    deploy.define_singleton_method(:release) { nil }

    msg = job.send(:build_message, deploy, "deploy_failed")
    assert_includes msg, "my-app"
    assert_includes msg, "deploy failed"
  end
end
