require "rails_helper"

# PR B — Dashboard::BaseController#current_team session resolution.
RSpec.describe Dashboard::AppsController, type: :controller do
  include Devise::Test::ControllerHelpers

  let(:user) { users(:one) }
  let(:own)  { teams(:one) }

  before { sign_in user }

  it "defaults to the user's personal team when no session cookie" do
    get :index
    expect(controller.send(:current_team)).to eq(user.personal_team)
  end

  it "respects session[:current_team_id] when set to a team the user belongs to" do
    session[:current_team_id] = own.id
    get :index
    expect(controller.send(:current_team)).to eq(own)
  end

  it "ignores a session cookie pointing at a non-member team and falls back to personal" do
    session[:current_team_id] = teams(:two).id
    get :index
    expect(controller.send(:current_team)).to eq(user.personal_team)
  end
end
