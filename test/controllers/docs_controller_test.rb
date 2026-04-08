require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /docs redirects to getting-started" do
    get "/docs"
    assert_response :success
  end

  test "GET /docs/getting-started/sign-up renders page" do
    get "/docs/getting-started/sign-up"
    assert_response :success
    assert_select "h1", /Sign Up/
  end

  test "GET /docs/nonexistent returns 404" do
    get "/docs/nonexistent"
    assert_response :not_found
  end
end
