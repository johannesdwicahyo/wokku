# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "#consume_second_factor!" do
  let(:user) { create(:user, otp_secret: User.generate_otp_secret, otp_required_for_login: true) }

  it "accepts a current TOTP once" do
    code = user.current_otp
    expect(user.consume_second_factor!(code)).to be true
    expect(user.consume_second_factor!(code)).to be false
  end

  it "accepts a recovery code once, ignoring whitespace and dashes" do
    code = user.generate_otp_backup_codes!.first
    user.save!
    messy = " #{code[0, 5]}-#{code[5..]} "
    expect(user.consume_second_factor!(messy)).to be true
    expect(user.reload.otp_backup_codes.size).to eq(9)
    expect(user.consume_second_factor!(code)).to be false
  end

  it "generates 10 recovery codes of 20 hex characters" do
    codes = user.generate_otp_backup_codes!
    expect(codes.size).to eq(10)
    expect(codes).to all(match(/\A\h{20}\z/))
  end

  it "rejects garbage and blanks" do
    user.generate_otp_backup_codes!
    user.save!
    [ nil, "", "  ", "000000", "not-a-code", "a" * 200 ].each do |junk|
      expect(user.consume_second_factor!(junk)).to be(false), junk.inspect
    end
  end
end

RSpec.describe User, "#consume_second_factor! hardening" do
  let(:user) { create(:user, otp_secret: User.generate_otp_secret, otp_required_for_login: true) }

  it "M2: checks only TOTP for 6 digits and only recovery codes for the recovery format" do
    expect(user).not_to receive(:invalidate_otp_backup_code!)
    user.consume_second_factor!("123456")
    other = User.find(user.id)
    expect(other).not_to receive(:validate_and_consume_otp!)
    other.consume_second_factor!("ab" * 10)
  end

  it "M2: rejects input in neither format without hashing" do
    expect(Devise::Encryptor).not_to receive(:compare)
    expect(user.consume_second_factor!("12345")).to be false
    expect(user.consume_second_factor!("zz" * 10)).to be false
  end

  it "M2: accepts an upper-cased recovery code" do
    code = user.generate_otp_backup_codes!.first
    user.save!
    expect(user.consume_second_factor!(code.upcase)).to be true
  end

  it "M1: a recovery code consumed by another process is not accepted by a stale copy" do
    code = user.generate_otp_backup_codes!.first
    user.save!
    stale = User.find(user.id)
    expect(user.consume_second_factor!(code)).to be true
    expect(stale.consume_second_factor!(code)).to be false
  end
end
