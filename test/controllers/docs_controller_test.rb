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

  test "sidebar navigation is present" do
    get "/docs/getting-started/sign-up"
    assert_select "nav a[href='/docs/getting-started/sign-up']"
  end

  test "tabs render with channel buttons" do
    get "/docs/getting-started/sign-up"
    assert_response :success
    assert_select ".docs-tabs"
    assert_select ".docs-tab-btn", minimum: 2
    assert_select ".docs-tab-panel", minimum: 2
  end

  test "search index returns JSON" do
    get "/docs/search-index.json"
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    assert json.any? { |entry| entry["path"] == "getting-started/sign-up" }
    assert json.first.key?("title")
    assert json.first.key?("headings")
    assert json.first.key?("excerpt")
  end

  test "code blocks have syntax highlighting" do
    get "/docs/getting-started/first-deploy"
    assert_response :success
    assert_select ".docs-code-block"
  end

  test "prev/next links point to correct pages" do
    get "/docs/getting-started/first-deploy"
    assert_select ".docs-prev-next a[href='/docs/getting-started/sign-up']"
    assert_select ".docs-prev-next a[href='/docs/getting-started/connect-server']"
  end

  test "table of contents is generated from headings" do
    get "/docs/getting-started/sign-up"
    assert_select "[data-controller='docs-toc']"
  end

  test "all sidebar pages are accessible" do
    sidebar = YAML.load_file(Rails.root.join("docs/sidebar.yml"))
    sidebar.each do |section|
      section["items"].each do |item|
        get "/docs/#{item['path']}"
        assert_response :success, "Failed to load /docs/#{item['path']}"
      end
    end
  end
end
