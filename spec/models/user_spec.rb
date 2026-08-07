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
end
