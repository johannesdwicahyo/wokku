# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCodes::Issue, type: :model do
  include ActionMailer::TestHelper

  let(:user) { users(:one) }

  def issue(email = user.email, ip: "1.2.3.4", locale: "en")
    described_class.call(email: email, ip: ip, locale: locale)
  end

  # Mails actually delivered (ActionMailer :test), via the queued jobs.
  def sent_codes
    perform_enqueued_jobs(only: SignInCodeMailer::DeliveryJob)
    ActionMailer::Base.deliveries.select { |m| m.subject.to_s.match?(/\d{6}\z/) }
  end

  def code_in(mail) = mail.subject[/\d{6}\z/]

  before { ActionMailer::Base.deliveries.clear }

  it "stores only the digest, never the plain code, valid for 10 minutes" do
    freeze_time do
      expect(issue("  #{user.email.upcase} ").status).to eq(:sent)
      rec = SignInCode.sole
      expect(rec.email).to eq(user.email)
      expect(rec.ip).to eq("1.2.3.4")
      expect(rec.expires_at).to eq(10.minutes.from_now)
      expect(rec.code_digest).to match(/\A\h{64}\z/)
      code = code_in(sent_codes.sole)
      expect(code).to match(/\A\d{6}\z/)
      expect(SignInCode.column_names).not_to include("code")
      expect(rec.code_digest).not_to include(code)
      expect(rec.matches?(code)).to be(true)
    end
  end

  it "zero-pads small codes" do
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(42)
    issue
    expect(code_in(sent_codes.sole)).to eq("000042")
  end

  it "mails in the user's locale when the user exists, else the request locale" do
    user.update!(locale: "id")
    issue(locale: "en")
    expect(sent_codes.last.subject).to start_with("Kode masuk")
    issue("new-person@example.com", locale: "id")
    expect(sent_codes.last.subject).to start_with("Kode masuk")
    issue("other-person@example.com", locale: "en")
    expect(sent_codes.last.subject).to start_with("Your Wokku")
  end

  it "enforces a 45 s cooldown with the seconds left, then kills the earlier code" do
    freeze_time do
      issue
      travel 10.seconds
      result = issue
      expect(result.status).to eq(:cooldown)
      expect(result.wait).to eq(35)
      expect(SignInCode.count).to eq(1)

      travel 35.seconds
      expect(issue.status).to eq(:sent)
      old, fresh = SignInCode.order(:created_at).to_a
      expect(old.consumed_at).to be_present
      expect(fresh.consumed_at).to be_nil
    end
  end

  it "answers :sent for a malformed email and sends nothing" do
    [ "", nil, "not-an-email", "a@b c", "x" * 300 + "@e.co" ].each do |bad|
      expect(issue(bad).status).to eq(:sent)
    end
    expect(sent_codes).to be_empty
  end

  context "when the email may not sign in it still answers :sent (and cools down) but mails nothing" do
    it "unknown email on closed registration" do
      Wokku.configure { |c| c.open_registration = false }
      expect(issue("stranger@example.com").status).to eq(:sent)
      expect(issue("stranger@example.com").status).to eq(:cooldown) # same shape as a real account
      expect(sent_codes).to be_empty
    ensure
      Wokku.configure { |c| c.open_registration = true }
    end

    it "suspended user" do
      user.update_columns(abuse_suspended_at: Time.current)
      expect(issue.status).to eq(:sent)
      expect(sent_codes).to be_empty
    end

    it "sign-up guard says no" do
      seen = nil
      Wokku.configure { |c| c.email_signup_guard = ->(email:, ip:) { seen = [ email, ip ]; false } }
      expect(issue("new-person@example.com").status).to eq(:sent)
      expect(seen).to eq([ "new-person@example.com", "1.2.3.4" ])
      expect(sent_codes).to be_empty
    ensure
      Wokku.configure { |c| c.email_signup_guard = nil }
    end

    it "the admin email without a seeded admin" do
      stub_const("User::ADMIN_EMAIL", "boss@example.com")
      expect(issue("boss@example.com").status).to eq(:sent)
      expect(sent_codes).to be_empty
    end
  end

  it "mails a new email on open registration and the seeded admin" do
    issue("new-person@example.com")
    issue(users(:admin).email)
    expect(sent_codes.size).to eq(2)
  end

  it "keeps the plain code out of the queued job's arguments" do
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(123456)
    issue
    expect(enqueued_jobs.size).to eq(1)
    expect(enqueued_jobs.to_json).not_to include("123456")
    expect(code_in(sent_codes.sole)).to eq("123456")
  end

  it "stores an unmatchable digest for rows it won't mail" do
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(123456)
    user.update_columns(abuse_suspended_at: Time.current)
    issue
    rec = SignInCode.sole
    expect(rec.code_digest).to eq("-")
    expect(rec.matches?("123456")).to be(false)
  end

  it "normalises NFKC and edge whitespace, rejects inner whitespace and invisible characters" do
    expect(issue("\u00A0#{user.email}\u3000").status).to eq(:sent)
    expect(SignInCode.sole.email).to eq(user.email)
    expect(sent_codes.size).to eq(1)

    [ "user-\u200Bone@example.com", "user-one@exa\u00A0mple.com", "user-one@example.com\u0000x", "us\ter@example.com" ].each do |bad|
      expect(issue(bad).status).to eq(:sent)
    end
    expect(SignInCode.count).to eq(1)
    expect(sent_codes.size).to eq(1)
  end

  describe "daily cap after 3 locked codes" do
    def lock_code(at)
      SignInCode.create!(email: user.email, code_digest: "x", expires_at: at + 10.minutes, attempts: 5, created_at: at)
    end

    def paused_notices = ActionMailer::Base.deliveries.select { |m| m.subject.to_s.include?("paused") || m.subject.to_s.include?("dijeda") }

    it "pauses deliverable codes for 24 h from the latest lock and tells the owner once" do
      freeze_time do
        lock_code(20.hours.ago)
        lock_code(10.hours.ago)
        lock_code(2.hours.ago)

        expect(issue.status).to eq(:sent)
        expect(SignInCode.order(:created_at).last.code_digest).to eq("-")
        expect(sent_codes).to be_empty
        expect(paused_notices.size).to eq(1)
        expect(paused_notices.first.to).to eq([ user.email ])
        expect(CGI.unescapeHTML(paused_notices.first.text_part.body.decoded)).to include("Sign-in by code is paused for 24 hours")

        travel 1.minute
        expect(issue.status).to eq(:sent) # normal cooldown rules still apply in between
        expect(paused_notices.size).to eq(1) # one notice per 24 h

        travel_to(2.hours.ago + 24.hours + 1.minute) # latest lock + 24 h
        issue
        expect(sent_codes.size).to eq(1)
      end
    end

    it "answers the same and mails nothing for an unknown email" do
      SignInCode.where(email: user.email).delete_all
      3.times { |i| SignInCode.create!(email: "ghost@example.com", code_digest: "x", expires_at: 1.hour.from_now, attempts: 5, created_at: (i + 1).hours.ago) }
      expect(issue("ghost@example.com").status).to eq(:sent)
      expect(ActionMailer::Base.deliveries.tap { perform_enqueued_jobs }).to be_empty
    end

    it "never pauses on locked dummy (undelivered) rows" do
      3.times { |i| SignInCode.create!(email: user.email, code_digest: SignInCode::UNMATCHABLE, expires_at: 1.hour.from_now, attempts: 5, created_at: (i + 1).hours.ago) }
      issue
      expect(sent_codes.size).to eq(1)
    end

    it "pauses a real victim only on delivered codes that ended locked" do
      lock_code(3.hours.ago)
      lock_code(2.hours.ago)
      SignInCode.create!(email: user.email, code_digest: SignInCode::UNMATCHABLE, expires_at: 1.hour.from_now, attempts: 5, created_at: 1.hour.ago)
      issue
      expect(sent_codes.size).to eq(1)
      expect(SignInCodes::Issue.paused?(user.email)).to be(false)
      lock_code(1.minute.ago)
      expect(SignInCodes::Issue.paused?(user.email)).to be(true)
    end

    it "is not triggered by two locks" do
      lock_code(3.hours.ago)
      lock_code(2.hours.ago)
      issue
      expect(sent_codes.size).to eq(1)
    end

    it "copy exists in Indonesian" do
      mail = SignInCodeMailer.paused(email: "a@b.co", locale: "id")
      expect(mail.subject).to include("dijeda")
    end
  end
end
