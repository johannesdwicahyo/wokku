require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects successfully when user is authenticated via warden" do
    user = users(:one)
    connect env: { "warden" => stub_warden(user) }
    assert_equal user, connection.current_user
  end

  test "rejects connection when warden has no user" do
    assert_reject_connection do
      connect env: { "warden" => stub_warden(nil) }
    end
  end

  private

  def stub_warden(user)
    warden = Object.new
    warden.define_singleton_method(:user) { user }
    warden
  end
end
