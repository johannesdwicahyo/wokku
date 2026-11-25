require "rails_helper"

RSpec.describe "mailer layout" do
  it "keeps the mailer layout light" do
    html = UpdateMailer.available(users(:admin), current: "1", latest: "2").html_part.body.to_s
    expect(html).to include("wokku-tile.png")
    expect(html).to match(%r{https?://[^"]+/wokku-tile\.png})
    expect(html).to match(/background:#(ffffff|f6f6f5)/)
    expect(html).not_to include("color-scheme: dark")
  end
end
