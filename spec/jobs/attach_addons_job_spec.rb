# frozen_string_literal: true

require "rails_helper"

RSpec.describe AttachAddonsJob do
  include ActiveJob::TestHelper

  let(:user) { users(:one) }
  let(:app) { AppRecord.create!(name: "jobapp", team: teams(:one), server: servers(:one), creator: user) }
  let(:items) { [ { kind: "shared", engine: "postgres" } ] }

  it "attaches the items, then enqueues the first GitHub deploy" do
    user.update!(github_installation_id: 7)
    result = Addons::AttachOnCreate::Result.new(attached: [ "pg" ], failed: [], outcomes: [])
    expect(Addons::AttachOnCreate).to receive(:call).with(app: app, user: user, items: items).ordered.and_return(result)
    expect(GithubRepos).to receive(:start_deploy).with(app, "me/repo", "main", installation_id: 7).ordered
    described_class.perform_now(app.id, user.id, items, { "repo" => "me/repo", "branch" => "main" })
  end

  it "logs an app activity for a failed shared item and still deploys" do
    result = Addons::AttachOnCreate::Result.new(attached: [], failed: [ { label: "postgres", error: "boom" } ], outcomes: [])
    allow(Addons::AttachOnCreate).to receive(:call).and_return(result)
    expect { described_class.perform_now(app.id, user.id, items) }
      .to change { Activity.where(action: "app.addon_attach_failed", target_id: app.id).count }.by(1)
    expect(Activity.find_by(action: "app.addon_attach_failed").metadata).to include("label" => "postgres", "error" => "boom")
  end
end
