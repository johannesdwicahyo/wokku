require "rails_helper"

RSpec.describe "New device alert", type: :request do
  let(:user) { users(:one) }

  before { ActionMailer::Base.deliveries.clear }

  it "records a KnownDevice and enqueues an alert email on first sign-in from a device" do
    expect {
      perform_enqueued_jobs do
        KnownDevice.track!(user: user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
      end
    }.to change { user.known_devices.count }.by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present, "expected SecurityMailer.new_device_sign_in to send"
    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to include("New sign-in")
  end

  it "does not re-alert a returning user from the same device" do
    KnownDevice.track!(user: user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
    ActionMailer::Base.deliveries.clear

    expect {
      perform_enqueued_jobs do
        KnownDevice.track!(user: user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
      end
    }.not_to change { user.known_devices.count }
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "triggers a new alert for a new IP with the same user-agent" do
    KnownDevice.track!(user: user, ip: "203.0.113.42", user_agent: "Mozilla/5.0 Chrome/120")
    ActionMailer::Base.deliveries.clear

    expect {
      perform_enqueued_jobs do
        KnownDevice.track!(user: user, ip: "198.51.100.9", user_agent: "Mozilla/5.0 Chrome/120")
      end
    }.to change { user.known_devices.count }.by(1)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
