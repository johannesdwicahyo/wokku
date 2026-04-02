require "test_helper"

class Dashboard::DomainsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Null object for Dokku::Domains — absorbs any call
  class FakeDokkuDomains
    def add(*); end
    def remove(*); end
    def enable_ssl(*); end
  end

  setup do
    @user   = users(:two)
    @app    = app_records(:two)
    @domain = domains(:two)

    # Patch Dokku::Client + Dokku::Domains so no SSH calls are made
    fake_client = Object.new
    @orig_client_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*| fake_client }

    fake_domains = FakeDokkuDomains.new
    @orig_domains_new = Dokku::Domains.method(:new)
    Dokku::Domains.define_singleton_method(:new) { |*| fake_domains }
  end

  teardown do
    Dokku::Client.define_singleton_method(:new, @orig_client_new)
    Dokku::Domains.define_singleton_method(:new, @orig_domains_new)
  end

  # --- Auth guard ---

  test "redirects to login when not authenticated on index" do
    sign_out :user
    get "/dashboard/apps/#{@app.id}/domains"
    assert_response :redirect
  end

  # --- index ---

  test "shows domains index when authenticated" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/domains"
    assert_response :success
  end

  # --- create ---

  test "creates domain and redirects" do
    sign_in @user
    assert_difference "@app.domains.count", 1 do
      post "/dashboard/apps/#{@app.id}/domains",
           params: { domain: { hostname: "new.example.com" } }
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/domains"
  end

  # --- ssl ---

  test "enables ssl for a domain and redirects" do
    sign_in @user
    post "/dashboard/apps/#{@app.id}/domains/#{@domain.id}/ssl"
    assert_redirected_to "/dashboard/apps/#{@app.id}/domains"
  end

  # --- destroy ---

  test "destroys domain and redirects" do
    sign_in @user
    assert_difference "@app.domains.count", -1 do
      delete "/dashboard/apps/#{@app.id}/domains/#{@domain.id}"
    end
    assert_redirected_to "/dashboard/apps/#{@app.id}/domains"
  end
end
