require "rails_helper"

RSpec.describe UpdateMailer do
  it "tells the admin the versions and the one update command" do
    mail = described_class.available(users(:admin), current: "2026.11.16-f698248", latest: "2026.11.20-abc1234")
    expect(mail.to).to eq([ users(:admin).email ])
    expect(mail.subject).to eq("Wokku 2026.11.20-abc1234 is available")
    body = mail.text_part.body.to_s
    expect(body).to include("2026.11.16-f698248", "2026.11.20-abc1234", "cd /opt/wokku && sudo bash install.sh", "WOKKU_UPDATE_CHECK=0")
  end
end
