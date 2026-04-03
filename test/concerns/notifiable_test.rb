require "test_helper"

class NotifiableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  class TestJob < ApplicationJob
    include Notifiable
    public :fire_notifications
  end

  setup do
    @user = users(:two)
    @team = teams(:two)
    @app = app_records(:two)
    @deploy = @app.deploys.create!(status: :succeeded, commit_sha: "abc1234")
    Notification.where(team: @team).delete_all
  end

  test "fire_notifications enqueues NotifyJob for each notification" do
    Notification.create!(team: @team, channel: :push, events: ["deploy_succeeded"])
    Notification.create!(team: @team, channel: :slack, events: ["deploy_succeeded"], config: { "url" => "https://hooks.slack.com/test" })

    job = TestJob.new
    assert_enqueued_jobs 2, only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end

  test "fire_notifications handles nil team" do
    job = TestJob.new
    assert_nothing_raised do
      job.fire_notifications(nil, "deploy_succeeded", @deploy)
    end
  end

  test "fire_notifications does nothing without notifications" do
    job = TestJob.new
    assert_no_enqueued_jobs only: NotifyJob do
      job.fire_notifications(@team, "deploy_succeeded", @deploy)
    end
  end
end
