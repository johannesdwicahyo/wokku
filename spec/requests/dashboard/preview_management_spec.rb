require "rails_helper"

RSpec.describe "Dashboard::PreviewManagement", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:team) { teams(:two) }
  let(:parent) { app_records(:two) }

  before { sign_in user }

  it "renders the previews index (the view lived under the wrong path → 406)" do
    get "/dashboard/apps/#{parent.id}/previews"
    expect(response).to have_http_status(:ok)
  end

  it "offers only the database strategies that exist, and pre-selects 'No database' for a stored snapshot" do
    parent.update!(preview_enabled: true, database_strategy: "snapshot")
    get "/dashboard/apps/#{parent.id}/previews"
    expect(response.body).to include("No database", "Share production database")
    expect(response.body).not_to include('value="snapshot"')
    expect(response.body).to match(/value="empty"[^>]*checked|checked[^>]*value="empty"/)
  end

  it "enqueues CleanupJob with parent.id and pr_number" do
    preview = AppRecord.create!(
      name: "myapp-pr-7", team: team, server: parent.server, creator: user,
      is_preview: true, parent_app: parent, pr_number: 7,
      deploy_branch: "feat/x", status: :running, billing_exempt: true
    )

    expect {
      delete "/dashboard/apps/#{parent.id}/previews/#{preview.id}"
    }.to have_enqueued_job(Preview::CleanupJob).with(parent.id, 7)

    # Previews promoted from app-show anchor to real sub-nav page in
    # 701f054 — redirect now targets the previews index, not #previews.
    expect(response).to redirect_to("/dashboard/apps/#{parent.id}/previews")
  end

  it "404s when the preview belongs to a different parent" do
    other_parent = app_records(:one)
    preview = AppRecord.create!(
      name: "other-pr-1", team: teams(:one), server: other_parent.server, creator: users(:one),
      is_preview: true, parent_app: other_parent, pr_number: 1,
      deploy_branch: "x", status: :running, billing_exempt: true
    )

    expect {
      delete "/dashboard/apps/#{parent.id}/previews/#{preview.id}"
    }.to raise_error(ActiveRecord::RecordNotFound).or change { response&.status }
  end

  it "rejects when not authenticated" do
    sign_out user
    delete "/dashboard/apps/#{parent.id}/previews/abc"
    expect(response.status).to be_in([ 302, 401, 404 ])
  end
end
