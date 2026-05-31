# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Ai", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:deploy) { app_record.deploys.create!(status: "failed", log: "build failed") }

  before { sign_in user }

  it "returns a turbo stream when requested via turbo_stream" do
    allow_any_instance_of(AiDebugger).to receive(:diagnose).and_return(diagnosis: "Try bundle install")
    post dashboard_ai_diagnose_path, params: { deploy_id: deploy.id }, as: :turbo_stream
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/turbo-stream/)
  end

  it "redirects to the deploy page on HTML request" do
    allow_any_instance_of(AiDebugger).to receive(:diagnose).and_return(diagnosis: "ok")
    post dashboard_ai_diagnose_path, params: { deploy_id: deploy.id }
    expect(response).to redirect_to(dashboard_app_deploy_path(app_record, deploy))
  end

  it "requires authentication" do
    sign_out user
    post dashboard_ai_diagnose_path, params: { deploy_id: deploy.id }
    expect(response).to have_http_status(:redirect)
  end
end
