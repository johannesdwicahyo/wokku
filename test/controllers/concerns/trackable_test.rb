require "test_helper"

# Trackable is included in Api::V1::BaseController and Dashboard::BaseController.
# We test it through the API layer (no browser session needed).
# Dokku SSH calls are stubbed to avoid real network connections in tests.
class TrackableTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "trackable_test@example.com", password: "password123456")
    @team = Team.create!(name: "Trackable Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "track-server", host: "10.0.0.1", team: @team)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "trackable-token")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  # Stub Dokku::Apps#create so no SSH connection is attempted.
  def with_stubbed_dokku
    original = Dokku::Apps.instance_method(:create)
    Dokku::Apps.define_method(:create) { |*| nil }
    yield
  ensure
    Dokku::Apps.define_method(:create, original)
  end

  test "track helper creates an Activity record" do
    with_stubbed_dokku do
      assert_difference "Activity.count", 1 do
        post api_v1_apps_path,
             params: { name: "tracked-app", server_id: @server.id },
             headers: auth_headers
      end
    end

    activity = Activity.order(:created_at).last
    assert_equal "app.created", activity.action
    assert_equal @user, activity.user
    assert_equal @team, activity.team
  end

  test "track records correct target name" do
    with_stubbed_dokku do
      post api_v1_apps_path,
           params: { name: "mytracked", server_id: @server.id },
           headers: auth_headers
    end

    activity = Activity.order(:created_at).last
    assert_equal "mytracked", activity.target_name
  end

  test "track records target_type as AppRecord" do
    with_stubbed_dokku do
      post api_v1_apps_path,
           params: { name: "typed-app", server_id: @server.id },
           headers: auth_headers
    end

    activity = Activity.order(:created_at).last
    assert_equal "AppRecord", activity.target_type
  end

  test "no Activity is created when action does not call track" do
    # GET index does not call track
    assert_no_difference "Activity.count" do
      get api_v1_apps_path, headers: auth_headers
    end
  end
end
