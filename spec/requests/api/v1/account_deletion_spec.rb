require "rails_helper"

RSpec.describe "POST /api/v1/account/deletion", type: :request do
  let(:user) { create(:user, email: "jane@example.com") }

  it "schedules deletion, signs out everywhere and returns purge_at" do
    other_token, = ApiToken.create_with_token!(user: user, name: "cli")
    DeviceToken.create!(user: user, token: "apns-1", platform: "ios", provider: "apns")
    expect {
      post "/api/v1/account/deletion", params: { confirm_email: "  Jane@Example.com " }, headers: api_v1_headers(user), as: :json
    }.to have_enqueued_mail(AccountMailer, :account_deletion_scheduled)
    expect(response).to have_http_status(:accepted)
    expect(Time.zone.parse(response.parsed_body["purge_at"])).to be_within(1.minute).of(3.days.from_now)
    expect(user.reload).to be_deletion_pending
    expect(other_token.reload.revoked_at).to be_present
    expect(user.api_tokens.active).to be_empty
    expect(user.device_tokens).to be_empty
  end

  it "422s a mismatched or blank confirm_email" do
    [ "other@example.com", "" ].each do |email|
      post "/api/v1/account/deletion", params: { confirm_email: email }, headers: api_v1_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload).not_to be_deletion_pending
    end
  end

  it "409s when deletion is already scheduled" do
    user.schedule_deletion!
    post "/api/v1/account/deletion", params: { confirm_email: user.email }, headers: api_v1_headers(user), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error_code"]).to eq("already_exists")
  end

  it "403s the admin" do
    admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
    post "/api/v1/account/deletion", params: { confirm_email: admin.email }, headers: api_v1_headers(admin), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(admin.reload).not_to be_deletion_pending
  end

  it "is atomic: a failure while signing out schedules nothing, stops no apps and sends no mail" do
    team_user = create(:user, :with_personal_team)
    create(:app_record, team: team_user.teams.first)
    allow_any_instance_of(User).to receive(:device_tokens).and_raise(ActiveRecord::StatementInvalid, "boom")
    expect {
      post "/api/v1/account/deletion", params: { confirm_email: team_user.email }, headers: api_v1_headers(team_user), as: :json
    }.not_to have_enqueued_job # neither the app-stop job nor the mail
    expect(User.find(team_user.id)).not_to be_deletion_pending
  end
end
