require "rails_helper"

# The Preferences card (language + currency) auto-submits on change. Its
# fields were nested under form_with(url:) without a scope, so they posted as
# "[user][locale]" and every change answered 400 ParameterMissing.
RSpec.describe "Profile preferences", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { users(:one) }

  before { sign_in user }

  it "names the preference fields user[...]" do
    get "/dashboard/profile"
    expect(response.body).to include('name="user[locale]"')
    expect(response.body).not_to include('name="[user][locale]"')
  end

  it "saves the language" do
    patch "/dashboard/profile", params: { user: { locale: "id" } }
    expect(response).to redirect_to("/dashboard/profile")
    expect(user.reload.locale).to eq("id")
  end
end
