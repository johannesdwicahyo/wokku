# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCodeMailer, type: :mailer do
  it "puts the code in the English subject and body" do
    mail = described_class.code(email: "a@b.co", code: "123456", locale: "en")
    expect(mail.to).to eq([ "a@b.co" ])
    expect(mail.subject).to eq("Your Wokku sign-in code: 123456")
    [ mail.html_part, mail.text_part ].each do |part|
      body = CGI.unescapeHTML(part.body.decoded)
      expect(body).to include("123456", "Works once, for 10 minutes", "If you didn't ask for this, ignore this email.")
    end
  end

  it "speaks Indonesian" do
    mail = described_class.code(email: "a@b.co", code: "654321", locale: "id")
    expect(mail.subject).to eq("Kode masuk Wokku kamu: 654321")
    expect(mail.text_part.body.decoded).to include("654321")
    expect(mail.text_part.body.decoded).not_to include("Works once")
  end

  it "falls back to the default locale for an unknown one" do
    expect(described_class.code(email: "a@b.co", code: "1", locale: "xx").subject).to start_with("Your Wokku")
  end

  it "never logs the job arguments (the code)" do
    expect(described_class.delivery_job.log_arguments?).to be(false)
  end
end
