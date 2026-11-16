require "rails_helper"

RSpec.describe "Shape-only apps render everywhere", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user)     { users(:one) }
  # NOTE: not named `app` — that clashes with ActionDispatch::IntegrationTest#app
  # (the Rack app `get`/`post` call under the hood), which breaks every request
  # in this spec with `NoMethodError: undefined method 'call' for an instance
  # of AppRecord`. Confirmed via RED run before this rename.
  let(:shape_app) { app_records(:one) }

  before do
    shape_app.dyno_allocations.destroy_all
    shape_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.5, memory_mb: 1024)
    sign_in user
  end

  %w[/dashboard/apps /dashboard/usage].each do |path|
    it "GET #{path} renders" do
      allow(Wokku).to receive(:cloud?).and_return(true) # usage page is cloud-only
      get path
      expect(response).to have_http_status(:ok)
    end
  end

  it "GET app overview renders the shape label" do
    get "/dashboard/apps/#{shape_app.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0.5 vCPU · 1 GB")
  end

  it "GET resources deferred frame renders" do
    get "/dashboard/apps/#{shape_app.id}/resources", params: { deferred: 1 }
    expect(response).to have_http_status(:ok)
  end
end
