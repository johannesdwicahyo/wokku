# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCodes::Verify, type: :model do
  let(:user) { users(:one) }

  def code_for(email, code: "123456", **attrs)
    SignInCode.create!(email: email, code_digest: SignInCode.digest(email, code), expires_at: 10.minutes.from_now, **attrs)
    code
  end

  def verify(email, code, ip: "1.2.3.4")
    described_class.call(email: email, code: code, ip: ip)
  end

  it "signs in the existing user once (single use), with a normalised email" do
    code = code_for(user.email)
    result = verify(" #{user.email.upcase} ", code)
    expect(result.user).to eq(user)
    expect(result.error).to be_nil
    expect(result.new_user).to be(false)
    expect(SignInCode.sole.consumed_at).to be_present
    expect(verify(user.email, code).error).to eq(:invalid)
  end

  it "expires after 10 minutes" do
    code = code_for(user.email)
    travel 10.minutes + 1.second do
      expect(verify(user.email, code).error).to eq(:expired)
    end
  end

  it "allows 5 wrong attempts, then the 6th (even the right code) is :locked" do
    code = code_for(user.email)
    5.times { expect(verify(user.email, "000000").error).to eq(:invalid) }
    result = verify(user.email, code)
    expect(result.error).to eq(:locked)
    expect(result.user).to be_nil
    expect(SignInCode.sole.attempts).to eq(5)
  end

  it "uses only the newest unconsumed code" do
    old = code_for(user.email, code: "111111", created_at: 1.minute.ago)
    code_for(user.email, code: "222222")
    expect(verify(user.email, old).error).to eq(:invalid)
  end

  it "does not accept email A's code for email B" do
    code = code_for(user.email)
    code_for(users(:two).email, code: "999999")
    expect(verify(users(:two).email, code).error).to eq(:invalid)
    expect(verify("nobody@example.com", code).error).to eq(:invalid)
  end

  it "refuses an inactive user with the same :invalid as a wrong code" do
    user.update_columns(abuse_suspended_at: Time.current)
    code = code_for(user.email)
    expect(verify(user.email, code)).to have_attributes(user: nil, error: :invalid)
  end

  it "rejects a non-6-digit code" do
    code_for(user.email)
    expect(verify(user.email, "12345").error).to eq(:invalid)
    expect(verify(user.email, nil).error).to eq(:invalid)
  end

  describe "new accounts" do
    let(:email) { "new-person@example.com" }

    it "creates the user with the OAuth path's fields and post-create effects" do
      code = code_for(email)
      result = nil
      expect { result = verify(email, code) }
        .to change(User, :count).by(1)
        .and have_enqueued_mail(OnboardingMailer, :welcome)
      user = result.user
      expect(result.new_user).to be(true)
      expect(user).to be_persisted
      expect(user.name).to eq("new-person")
      expect(user.email_provider_verified).to be(true)
      expect(user.encrypted_password).to be_present
      expect(user.personal_team).to be_present
      expect(user.team_memberships.sole.role).to eq("admin")
      expect(user.plan).to eq(Plan.find_by(key: "free"))
    end

    it "creates nobody when registration closed in the meantime" do
      code = code_for(email)
      Wokku.configure { |c| c.open_registration = false }
      expect { expect(verify(email, code)).to have_attributes(user: nil, error: :invalid) }.not_to change(User, :count)
    ensure
      Wokku.configure { |c| c.open_registration = true }
    end

    it "never creates the admin email; only signs into the seeded admin" do
      stub_const("User::ADMIN_EMAIL", "boss@example.com")
      code = code_for("boss@example.com")
      expect { expect(verify("boss@example.com", code).error).to eq(:invalid) }.not_to change(User, :count)

      stub_const("User::ADMIN_EMAIL", users(:admin).email)
      code = code_for(users(:admin).email)
      expect(verify(users(:admin).email, code).user).to eq(users(:admin))
    end
  end

  it "a refused or unknown email can never verify, even knowing the code" do
    allow(SecureRandom).to receive(:random_number).with(10**6).and_return(123456)
    Wokku.configure { |c| c.email_signup_guard = ->(email:, ip:) { false } }
    SignInCodes::Issue.call(email: "refused@example.com", ip: "1.2.3.4", locale: "en")
    expect { expect(verify("refused@example.com", "123456").error).to eq(:invalid) }.not_to change(User, :count)

    Wokku.configure { |c| c.email_signup_guard = nil; c.open_registration = false }
    travel 1.minute do
      SignInCodes::Issue.call(email: "unknown@example.com", ip: "1.2.3.4", locale: "en")
      Wokku.configure { |c| c.open_registration = true }
      expect { expect(verify("unknown@example.com", "123456").error).to eq(:invalid) }.not_to change(User, :count)
    end
  ensure
    Wokku.configure { |c| c.email_signup_guard = nil; c.open_registration = true }
  end

  it "signs a new user in even if the welcome mail can't be queued" do
    allow(OnboardingMailer).to receive(:welcome).and_raise(StandardError, "queue down")
    code = code_for("new-person@example.com")
    expect(verify("new-person@example.com", code).user).to be_persisted
  end
end
