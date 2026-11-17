require "rails_helper"

# The Wicara chat widget is Wokku Cloud's customer support. A self-hosted
# install must not load it (its admins' chats would land in our inbox).
RSpec.describe "Support chat widget", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }

  it "is not loaded on a self-hosted install" do
    allow(Wokku).to receive(:cloud?).and_return(false)
    get "/dashboard/apps"
    expect(response.body).not_to include("wicara.cloud/widget.js")
    get "/docs"
    expect(response.body).not_to include("wicara.cloud/widget.js")
  end

  it "is loaded on wokku.cloud" do
    allow(Wokku).to receive(:cloud?).and_return(true)
    get "/dashboard/apps"
    expect(response.body).to include("wicara.cloud/widget.js")
  end
end
