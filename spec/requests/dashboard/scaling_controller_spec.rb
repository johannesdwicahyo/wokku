# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Scaling", type: :request do
  # Legacy box-quota scaling path (resource builder off).
  before { allow(Wokku.config).to receive(:resource_builder?).and_return(false) }

  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    allow(Lifecycle::Ops).to receive(:converge!)
  end

  it "redirects to login when not authenticated on show" do
    get "/dashboard/apps/#{app_record.id}/scaling"
    expect(response).to have_http_status(:redirect)
  end

  it "scaling page redirects to merged Resources tab" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/scaling"
    expect(response).to redirect_to(dashboard_app_resources_path(app_record))
  end

  it "updates process scaling and redirects" do
    sign_in user
    patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 1 } }
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/scaling")
    expect(flash[:notice]).to match("Scaling updated")
  end

  it "redirects with alert when converge raises an unexpected error" do
    sign_in user
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(RuntimeError, "converge error")

    patch "/dashboard/apps/#{app_record.id}/scaling", params: { scaling: { web: 2 } }
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/scaling")
    expect(flash[:alert]).to match("Scaling failed")
  end
end

RSpec.describe "Dashboard::Scaling return_to overview", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:path)       { "/dashboard/apps/#{app_record.id}/scaling" }

  before do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    sign_in user
  end

  it "returns to the overview with the notice" do
    allow(Resources::ApplyChange).to receive(:call).and_return(double(ok: true))
    patch path, params: { scaling: { web: 2 }, return_to: "overview" }
    expect(response).to redirect_to(dashboard_app_path(app_record))
    expect(flash[:notice]).to eq("Scaling updated.")
  end

  it "returns to the overview with a refusal alert" do
    allow(Resources::ApplyChange).to receive(:call).and_return(double(ok: false, error: "over quota"))
    patch path, params: { scaling: { web: 2 }, return_to: "overview" }
    expect(response).to redirect_to(dashboard_app_path(app_record))
    expect(flash[:alert]).to eq("over quota")
  end

  it "still goes to scaling without return_to" do
    allow(Resources::ApplyChange).to receive(:call).and_return(double(ok: true))
    patch path, params: { scaling: { web: 2 } }
    expect(response).to redirect_to(path)
  end
end
