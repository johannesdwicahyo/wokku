# frozen_string_literal: true

require "rails_helper"

# An app whose deploys have all failed never ran, so it is "Not deployed"
# (:created), not "Crashed". Once a release has succeeded, a failed deploy
# keeps the existing :crashed behaviour.
RSpec.describe AppRecord, "#mark_deploy_failed!" do
  let(:app_record) { create(:app_record, status: :deploying) }

  it "leaves a never-deployed app :created" do
    create(:deploy, app_record: app_record, status: :failed)
    app_record.mark_deploy_failed!
    expect(app_record.reload.status).to eq("created")
  end

  it "marks an app that has run before :crashed" do
    create(:deploy, app_record: app_record, status: :succeeded)
    create(:deploy, app_record: app_record, status: :failed)
    app_record.mark_deploy_failed!
    expect(app_record.reload.status).to eq("crashed")
  end

  it "labels :created as Not deployed" do
    expect(Atoms::StatusPillComponent.new(status: "created").spec[:label]).to eq("Not deployed")
  end
end
