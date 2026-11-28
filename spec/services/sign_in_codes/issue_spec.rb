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

  before do
    ActionMailer::Base.deliveries.clear
    user.update_columns(email_provider_verified: true)
  end

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

  it "caps an email at 3 codes per 10 minutes (dummies included), waiting for the oldest to age out" do
    Wokku.configure { |c| c.open_registration = false } # stranger gets unmatchable dummy rows
    freeze_time do
      [ user.email, "stranger@example.com" ].each do |email|
        3.times { expect(issue(email).status).to eq(:sent); travel 46.seconds }
        result = issue(email)
        expect(result.status).to eq(:cooldown)
        expect(result.wait).to eq((10.minutes - 3 * 46.seconds).to_i)
        expect(SignInCode.where(email: email).count).to eq(3)
        travel result.wait.seconds
        expect(issue(email).status).to eq(:sent)
      end
    end
    expect(SignInCode.where(email: "stranger@example.com").pluck(:code_digest).uniq).to eq([ SignInCode::UNMATCHABLE ])
  ensure
    Wokku.configure { |c| c.open_registration = true }
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

    it "existing user whose email isn't provider-verified (a self-edited, possibly planted email)" do
      user.update_columns(email_provider_verified: false)
      expect(issue.status).to eq(:sent)
      expect(SignInCode.sole.code_digest).to eq(SignInCode::UNMATCHABLE)
      expect(sent_codes).to be_empty
    end

    it "the admin email without a seeded admin" do
      stub_const("User::ADMIN_EMAIL", "boss@example.com")
      expect(issue("boss@example.com").status).to eq(:sent)
      expect(sent_codes).to be_empty
    end
  end

  it "mails a new email on open registration and the seeded admin" do
    users(:admin).update_columns(email_provider_verified: true)
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
end
