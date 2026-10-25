require "rails_helper"

RSpec.describe "Sign-in page Apple button", type: :request do
  let(:apple_env) do
    { "APPLE_SERVICES_ID" => "cloud.wokku.signin", "APPLE_TEAM_ID" => "TEAM123456",
      "APPLE_KEY_ID" => "KEY1234567", "APPLE_PRIVATE_KEY" => "pem" }
  end

  it "shows Continue with Apple when Apple web sign-in is configured" do
    stub_const("ENV", ENV.to_h.merge(apple_env))
    get new_user_session_path
    expect(response.body).to include("Continue with Apple")
    expect(response.body).to include(user_apple_omniauth_authorize_path)
  end

  it "hides it when Apple is not configured" do
    stub_const("ENV", ENV.to_h.except(*apple_env.keys))
    get new_user_session_path
    expect(response.body).not_to include("Continue with Apple")
  end
end
