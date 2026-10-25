require "rails_helper"

RSpec.describe MobileAuthCode do
  let(:user) { create(:user) }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  it "issues a code it stores only as a digest" do
    code = described_class.issue!(user: user, code_challenge: challenge)
    rec = described_class.last
    expect(rec.code_digest).to eq(Digest::SHA256.hexdigest(code))
    expect(rec.attributes.values.map(&:to_s)).not_to include(code)
    expect(rec.expires_at).to be_within(5.seconds).of(2.minutes.from_now)
  end

  it "redeems once with the right verifier" do
    code = described_class.issue!(user: user, code_challenge: challenge)
    expect(described_class.redeem(code: code, code_verifier: verifier)).to eq(user)
    expect(described_class.redeem(code: code, code_verifier: verifier)).to be_nil
  end

  it "refuses the wrong verifier without burning the code" do
    code = described_class.issue!(user: user, code_challenge: challenge)
    expect(described_class.redeem(code: code, code_verifier: "x" * 43)).to be_nil
    expect(described_class.redeem(code: code, code_verifier: verifier)).to eq(user)
  end

  it "refuses an expired code" do
    code = described_class.issue!(user: user, code_challenge: challenge)
    travel 3.minutes do
      expect(described_class.redeem(code: code, code_verifier: verifier)).to be_nil
    end
  end

  it "refuses an unknown code" do
    expect(described_class.redeem(code: "nope", code_verifier: verifier)).to be_nil
  end

  it "deletes codes older than a day when redeeming" do
    old = described_class.issue!(user: user, code_challenge: challenge)
    described_class.update_all(created_at: 2.days.ago)
    described_class.redeem(code: "anything", code_verifier: verifier)
    expect(described_class.find_by(code_digest: Digest::SHA256.hexdigest(old))).to be_nil
  end

  describe "concurrent redemption" do
    # Real commits are needed for the row lock to matter; transactional tests share one connection.
    self.use_transactional_tests = false

    it "makes a second redeemer wait on the row lock, then refuse the spent code" do
      u = create(:user)
      code = described_class.issue!(user: u, code_challenge: challenge)
      second = nil
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.transaction do
          rec = described_class.lock.find_by!(code_digest: described_class.digest(code))
          second = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection { described_class.redeem(code: code, code_verifier: verifier) }
          end
          # Without the row lock the second redeemer would finish (and succeed) right away.
          expect(second.join(0.5)).to be_nil
          rec.update!(used_at: Time.current)
        end
      end
      expect(second.value).to be_nil
    ensure
      second&.kill
      described_class.where(user_id: u.id).delete_all
      u.destroy
    end
  end
end
