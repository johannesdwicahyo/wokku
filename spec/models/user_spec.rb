require "rails_helper"

RSpec.describe User do
  describe "plan default" do
    before do
      Plan.find_or_create_by!(key: "free") { |p| p.name = "Free" }
    end

    it "assigns the free plan on create when none is set" do
      user = build(:user, plan: nil)
      user.save!
      expect(user.plan.key).to eq("free")
    end
  end

  describe "validations (via Devise :validatable)" do
    it "is valid with email and password" do
      user = User.new(email: "test@example.com", password: "password123456")
      expect(user).to be_valid
    end

    it "is invalid without email" do
      user = User.new(password: "password123456")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it "is invalid with duplicate email" do
      existing = users(:one)
      user = User.new(email: existing.email, password: "password123456")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("has already been taken")
    end

    it "is invalid with short password" do
      user = User.new(email: "short@example.com", password: "abc")
      expect(user).not_to be_valid
    end
  end

  describe "role enum" do
    it "defaults to member" do
      user = User.new(email: "default-role@example.com", password: "password123456")
      expect(user.role).to eq("member")
    end

    it "fixture one has member role" do
      expect(users(:one).member?).to be true
      expect(users(:one).admin?).to be false
    end

    it "fixture admin has admin role" do
      expect(users(:admin).admin?).to be true
    end

    it "exposes member and admin enum values" do
      expect(User.roles).to eq({ "member" => 0, "admin" => 1 })
    end
  end

  describe "#two_factor_enabled?" do
    it "is false when otp_required_for_login is false" do
      user = users(:one)
      user.otp_required_for_login = false
      expect(user.two_factor_enabled?).to be_falsey
    end

    it "is true when otp_required_for_login is true" do
      user = users(:one)
      user.otp_required_for_login = true
      expect(user.two_factor_enabled?).to be true
    end
  end

  describe "Lockable" do
    it "tracks failed_attempts and locked_at columns" do
      user = users(:one)
      expect(user).to respond_to(:failed_attempts)
      expect(user).to respond_to(:locked_at)
    end

    it "lock_access! sets locked_at" do
      user = User.create!(email: "lockable@example.com", password: "password123456")
      user.lock_access!
      expect(user.reload.locked_at).not_to be_nil
    end

    it "unlock_access! clears locked_at" do
      user = User.create!(email: "unlockable@example.com", password: "password123456")
      user.lock_access!
      user.unlock_access!
      expect(user.reload.locked_at).to be_nil
    end
  end

  describe "associations" do
    it "responds to has_many associations" do
      user = users(:one)
      %i[api_tokens ssh_public_keys team_memberships teams device_tokens].each do |assoc|
        expect(user).to respond_to(assoc)
      end
    end
  end

  describe "#current_plan" do
    it "falls back to free plan when no subscription" do
      expect(users(:one).current_plan).to eq(plans(:free))
    end
  end

  # Phase 4 (1.8): the balance / deposit_balance / daily_debit_email helpers
  # were removed along with the deposit billing rail. Tests for them
  # are deleted; payment-method behavior is now covered by invoice specs.

  describe "#card_user?" do
    let(:user) { users(:admin) }
    it "returns true when payment_method_type is card" do
      user.update!(payment_method_type: "card")
      expect(user.card_user?).to be true
    end
  end

  describe "guided tour lifecycle" do
    let(:user) { users(:one) }

    it "advances the step only forward while the tour is active" do
      user.update!(onboarding_status: :active, onboarding_step: 1)
      user.advance_tour_to(3)
      expect(user.reload.onboarding_step).to eq(3)
      user.advance_tour_to(2)
      expect(user.reload.onboarding_step).to eq(3)
    end

    it "does not advance when the tour is not active" do
      user.update!(onboarding_status: :pending, onboarding_step: 0)
      user.advance_tour_to(4)
      expect(user.reload.onboarding_step).to eq(0)
    end

    it "skip_tour! marks the tour skipped" do
      user.update!(onboarding_status: :active)
      user.skip_tour!
      expect(user.reload).to be_onboarding_skipped
    end
  end

  describe "#schedule_deletion!" do
    it "still schedules deletion when an app stop fails to enqueue" do
      user = users(:one)
      allow(DokkuAppActionJob).to receive(:perform_later).and_raise(RuntimeError, "queue down")
      expect { user.schedule_deletion! }.not_to raise_error
      expect(user.reload.deletion_scheduled_at).to be_present
    end
  end

  describe "IDR-only launch mode defaults" do
    before { allow(Wokku::LaunchMode).to receive(:idr_only?).and_return(true) }

    it "defaults new signups to the deposit payment method" do
      user = create(:user, payment_method_type: "none")
      expect(user.payment_method_type).to eq("deposit")
    end

    it "renders idr as the effective currency regardless of the row" do
      user = build(:user, currency: "usd")
      expect(user.effective_currency).to eq("idr")
    end
  end

  describe "#effective_currency outside launch mode" do
    it "returns the user's own currency" do
      allow(Wokku::LaunchMode).to receive(:idr_only?).and_return(false)
      expect(build(:user, currency: "usd").effective_currency).to eq("usd")
    end
  end

  describe "admin email reservation" do
    it "rejects a member account using the admin email" do
      user = User.new(email: User::ADMIN_EMAIL, password: "password123456", role: :member)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("is reserved")
    end
  end

  describe "#ensure_personal_team!" do
    it "retries with the next candidate name after losing a unique-index race" do
      user = create(:user)
      calls = 0
      allow_any_instance_of(Team).to receive(:save).and_wrap_original do |m, *args|
        calls += 1
        raise ActiveRecord::RecordNotUnique if calls == 1
        m.call(*args)
      end
      team, created = user.ensure_personal_team!
      expect(created).to be(true)
      expect(team).to be_persisted
      expect(team.name).to end_with(" 2")
      expect(user.teams).to include(team)
    end
  end

  describe ".from_omniauth" do
    it "marks accounts created from a provider as email_provider_verified" do
      expect(User.from_omniauth(auth_hash(email: "fresh-oauth@example.com", uid: "fresh-1")).email_provider_verified).to be(true)
    end

    def auth_hash(provider: "github", uid: "uid-1", email:, name: "Octo", raw_info: {})
      OmniAuth::AuthHash.new(
        provider: provider, uid: uid,
        info: { email: email, name: name, image: "http://img", nickname: "octo" },
        extra: { raw_info: raw_info }
      )
    end

    context "with the admin email" do
      it "returns an unpersisted user when no seed admin exists" do
        allow(User).to receive(:find_by).and_call_original
        allow(User).to receive(:find_by).with(email: User::ADMIN_EMAIL, role: :admin).and_return(nil)
        result = User.from_omniauth(auth_hash(email: User::ADMIN_EMAIL))
        expect(result).not_to be_persisted
      end

      it "refuses to link an unverified email to the admin account" do
        result = User.from_omniauth(
          auth_hash(provider: "google_oauth2", email: User::ADMIN_EMAIL,
                    raw_info: { "email_verified" => false })
        )
        expect(result).not_to be_persisted
        expect(users(:admin).reload.provider).to be_blank
      end

      it "links a verified OAuth identity to the seed admin on first sign-in" do
        result = User.from_omniauth(
          auth_hash(provider: "google_oauth2", uid: "g-9",
                    email: User::ADMIN_EMAIL, raw_info: { "email_verified" => true })
        )
        expect(result).to eq(users(:admin))
        expect(result.reload.provider).to eq("google_oauth2")
        expect(result.uid).to eq("g-9")
      end
    end

    context "with open registration and an existing unlinked account (email-code user)" do
      let!(:code_user) { create(:user, email: "coder@example.com", email_provider_verified: true) }

      around do |ex|
        Wokku.configure { |c| c.email_sign_in = true }
        ex.run
      ensure
        Wokku.configure { |c| c.email_sign_in = nil }
      end

      it "does not link an account whose stored email isn't provider-verified (planted email)" do
        code_user.update_columns(email_provider_verified: false)
        result = User.from_omniauth(auth_hash(uid: "gh-plant", email: code_user.email))
        expect(result).not_to be_persisted
        expect(code_user.reload.provider).to be_blank
      end

      it "does not link at all with email sign-in off (as before the flag)" do
        Wokku.configure { |c| c.email_sign_in = false }
        result = User.from_omniauth(auth_hash(uid: "gh-off", email: code_user.email))
        expect(result).not_to be_persisted
        expect(code_user.reload.provider).to be_blank
      end

      it "links it on a verified GitHub email" do
        result = nil
        expect { result = User.from_omniauth(auth_hash(uid: "gh-code", email: "Coder@example.com")) }.not_to change(User, :count)
        expect(result).to eq(code_user)
        expect(code_user.reload).to have_attributes(provider: "github", uid: "gh-code", email_provider_verified: true)
      end

      it "does not link an unverified email (unpersisted, as before)" do
        result = User.from_omniauth(auth_hash(provider: "google_oauth2", uid: "g-x", email: code_user.email,
                                              raw_info: { "email_verified" => false }))
        expect(result).not_to be_persisted
        expect(code_user.reload.provider).to be_blank
      end

      it "never re-links an account that already has a provider" do
        code_user.update_columns(provider: "google_oauth2", uid: "g-1")
        result = User.from_omniauth(auth_hash(uid: "gh-other", email: code_user.email))
        expect(result).to eq(code_user)
        expect(code_user.reload).to have_attributes(provider: "google_oauth2", uid: "g-1")
      end
    end

    context "with open registration and an account from another provider (cross-provider sign-in)" do
      let!(:gh_user) do
        create(:user, email: "dev@example.com", email_provider_verified: true).tap do |u|
          u.update_columns(provider: "github", uid: "gh-dev", github_username: "devgh", avatar_url: "http://gh-img", name: "GH Name")
        end
      end
      let(:google) do
        auth_hash(provider: "google_oauth2", uid: "g-dev", email: "Dev@example.com", name: "Google Name",
                  raw_info: { "email_verified" => true })
      end

      around do |ex|
        Wokku.configure { |c| c.email_sign_in = true }
        ex.run
      ensure
        Wokku.configure { |c| c.email_sign_in = nil }
      end

      it "returns the GitHub account for a Google sign-in with the same verified email, unchanged" do
        before = gh_user.reload.attributes
        result = nil
        expect { result = User.from_omniauth(google) }.not_to change(User, :count)
        expect(result).to eq(gh_user)
        expect(gh_user.reload.attributes).to eq(before)
      end

      it "returns the same account again on a second Google sign-in" do
        first = User.from_omniauth(google)
        expect(User.from_omniauth(google)).to eq(first)
        expect(gh_user.reload).to have_attributes(provider: "github", uid: "gh-dev")
      end

      it "returns a Google account for a GitHub sign-in with the same email" do
        gh_user.update_columns(provider: "google_oauth2", uid: "g-orig")
        result = User.from_omniauth(auth_hash(uid: "gh-new", email: gh_user.email))
        expect(result).to eq(gh_user)
        expect(gh_user.reload).to have_attributes(provider: "google_oauth2", uid: "g-orig")
      end

      it "refuses an unverified Google email and creates nothing" do
        result = nil
        expect {
          result = User.from_omniauth(auth_hash(provider: "google_oauth2", uid: "g-dev", email: gh_user.email,
                                                raw_info: { "email_verified" => false }))
        }.not_to change(User, :count)
        expect(result).not_to be_persisted
      end

      it "refuses an account whose email isn't provider-verified (self-edited)" do
        gh_user.update_columns(email_provider_verified: false)
        expect(User.from_omniauth(google)).not_to be_persisted
        expect(User.from_omniauth(auth_hash(provider: "gitlab", uid: "gl-1", email: gh_user.email))).not_to be_persisted
      end

      it "refuses a second identity from the same provider (as before)" do
        expect(User.from_omniauth(auth_hash(uid: "gh-other", email: gh_user.email))).not_to be_persisted
        expect(gh_user.reload.uid).to eq("gh-dev")
      end

      it "does nothing new with email sign-in off (failure, as before)" do
        Wokku.configure { |c| c.email_sign_in = false }
        expect { expect(User.from_omniauth(google)).not_to be_persisted }.not_to change(User, :count)
        expect(gh_user.reload).to have_attributes(provider: "github", uid: "gh-dev")
      end
    end

    context "with closed registration" do
      before { allow(Wokku.config).to receive(:open_registration).and_return(false) }

      it "signs in an account already linked by provider+uid" do
        user = create(:user)
        user.update_columns(provider: "github", uid: "gh-1")
        expect(User.from_omniauth(auth_hash(uid: "gh-1", email: "other@example.com"))).to eq(user)
      end

      it "links an unlinked account by verified email" do
        user = create(:user)
        result = User.from_omniauth(auth_hash(uid: "gh-2", email: user.email))
        expect(result).to eq(user)
        expect(result.reload.provider).to eq("github")
        expect(result.uid).to eq("gh-2")
      end

      it "returns an unpersisted user for an unknown account" do
        result = User.from_omniauth(auth_hash(uid: "gh-3", email: "stranger@example.com"))
        expect(result).not_to be_persisted
      end
    end
  end

  describe ".oauth_email_verified?" do
    def auth(provider:, raw_info:)
      OmniAuth::AuthHash.new(provider: provider, extra: { raw_info: raw_info })
    end

    it "honors an explicit email_verified claim" do
      expect(User.oauth_email_verified?(auth(provider: "google_oauth2", raw_info: { "email_verified" => true }))).to be(true)
      expect(User.oauth_email_verified?(auth(provider: "google_oauth2", raw_info: { email_verified: false }))).to be(false)
    end

    it "trusts primary emails from github/gitlab/bitbucket when no claim exists" do
      expect(User.oauth_email_verified?(auth(provider: "github", raw_info: {}))).to be(true)
      expect(User.oauth_email_verified?(auth(provider: "google_oauth2", raw_info: {}))).to be(false)
    end

    it "treats a missing raw_info as unverified for OIDC providers" do
      auth = OmniAuth::AuthHash.new(provider: "google_oauth2", extra: nil)
      expect(User.oauth_email_verified?(auth)).to be(false)
    end
  end
end
