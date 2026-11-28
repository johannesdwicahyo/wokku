# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCodeMailer, type: :mailer do
  def token(code) = SignInCode.encrypt_code(code)

  it "puts the code in the English subject and body" do
    mail = described_class.code(email: "a@b.co", token: token("123456"), locale: "en")
    expect(mail.to).to eq([ "a@b.co" ])
    expect(mail.subject).to eq("Your Wokku sign-in code: 123456")
    [ mail.html_part, mail.text_part ].each do |part|
      body = CGI.unescapeHTML(part.body.decoded)
      expect(body).to include("123456", "Works once, for 10 minutes", "If you didn't ask for this, ignore this email.")
    end
  end

  it "speaks Indonesian" do
    mail = described_class.code(email: "a@b.co", token: token("654321"), locale: "id")
    expect(mail.subject).to eq("Kode masuk Wokku kamu: 654321")
    expect(mail.text_part.body.decoded).to include("654321")
    expect(mail.text_part.body.decoded).not_to include("Works once")
  end

  it "falls back to the default locale for an unknown one" do
    expect(described_class.code(email: "a@b.co", token: token("111111"), locale: "xx").subject).to start_with("Your Wokku")
  end

  it "sends nothing for an expired or forged token, and logs without the token" do
    expired = token("123456")
    allow(Rails.logger).to receive(:warn)
    travel 10.minutes + 1.second do
      [ expired, "forged", nil ].each do |t|
        expect(described_class.code(email: "a@b.co", token: t, locale: "en").message).to be_a(ActionMailer::Base::NullMail)
      end
    end
    expect(Rails.logger).to have_received(:warn).with(satisfy { |m| !m.include?(expired) }).at_least(:once)
  end

  it "the paused notice is localised" do
    mail = described_class.paused(email: "a@b.co", locale: "en")
    body = CGI.unescapeHTML(mail.text_part.body.decoded)
    expect(body).to include("Someone tried to sign in to your Wokku account with an email code.",
                            "Sign-in by code is paused for 24 hours.", "If this was you, use GitHub/Google or wait.")
  end

  it "never logs the job arguments" do
    expect(described_class.delivery_job.log_arguments?).to be(false)
  end
end
