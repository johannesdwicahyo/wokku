require "rails_helper"

RSpec.describe Notifiable do
  class NotifiableTestJob < ApplicationJob
    include Notifiable
    public :fire_notifications
  end

  let(:user)   { users(:two) }
  let(:team)   { teams(:two) }
  let(:app)    { app_records(:two) }
  let(:deploy) { app.deploys.create!(status: :succeeded, commit_sha: "abc1234") }
  let(:job)    { NotifiableTestJob.new }

  before { Notification.where(team: team).delete_all }

  it "enqueues a NotifyJob for each notification" do
    Notification.create!(team: team, channel: :push, events: [ "deploy_succeeded" ])
    Notification.create!(team: team, channel: :slack, events: [ "deploy_succeeded" ], config: { "url" => "https://hooks.slack.com/test" })

    expect {
      job.fire_notifications(team, "deploy_succeeded", deploy)
    }.to have_enqueued_job(NotifyJob).exactly(2).times
  end

  it "handles a nil team without raising" do
    expect {
      job.fire_notifications(nil, "deploy_succeeded", deploy)
    }.not_to raise_error
  end

  it "does nothing when there are no notifications" do
    expect {
      job.fire_notifications(team, "deploy_succeeded", deploy)
    }.not_to have_enqueued_job(NotifyJob)
  end
end
