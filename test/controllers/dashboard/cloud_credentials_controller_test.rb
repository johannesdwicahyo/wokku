require "test_helper"

class Dashboard::CloudCredentialsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
  end

  test "redirects to login when not authenticated on index" do
    get "/dashboard/cloud_credentials"
    assert_response :redirect
  end

  test "redirects to login when not authenticated on create" do
    post "/dashboard/cloud_credentials", params: {
      cloud_credential: { provider: "hetzner", api_key: "key123", name: "My Hetzner" }
    }
    assert_response :redirect
  end

  test "redirects to login when not authenticated on destroy" do
    cred = teams(:two).cloud_credentials.create!(provider: "hetzner", api_key: "key123", name: "Test")

    delete "/dashboard/cloud_credentials/#{cred.id}"
    assert_response :redirect
  end

  test "destroys cloud credential when authenticated" do
    sign_in @user
    cred = teams(:two).cloud_credentials.create!(provider: "hetzner", api_key: "key123", name: "Test2")

    assert_difference("CloudCredential.count", -1) do
      delete "/dashboard/cloud_credentials/#{cred.id}"
    end
    assert_response :redirect
    assert_redirected_to "/dashboard/servers"
  end
end
