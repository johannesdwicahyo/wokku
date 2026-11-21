require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { users(:one) }
  let!(:token_record_and_plain) { ApiToken.create_with_token!(user: user, name: "test-cli") }
  let(:token_record) { token_record_and_plain.first }
  let(:plain_token)  { token_record_and_plain.last }

  describe "Bearer token path" do
    it "connects with a valid Bearer token" do
      connect headers: { "Authorization" => "Bearer #{plain_token}" }
      expect(connection.current_user).to eq(user)
    end

    it "rejects with an invalid Bearer token" do
      expect {
        connect headers: { "Authorization" => "Bearer notarealtoken" }
      }.to have_rejected_connection
    end

    it "rejects a suspended user's Bearer token" do
      user.update!(abuse_suspended_at: Time.current)
      expect {
        connect headers: { "Authorization" => "Bearer #{plain_token}" }
      }.to have_rejected_connection
    end

    it "rejects with no auth at all" do
      expect { connect }.to have_rejected_connection
    end

    it "rejects with a revoked token" do
      token_record.revoke!
      expect {
        connect headers: { "Authorization" => "Bearer #{plain_token}" }
      }.to have_rejected_connection
    end

    it "rejects with an expired token" do
      token_record.update!(expires_at: 1.hour.ago)
      expect {
        connect headers: { "Authorization" => "Bearer #{plain_token}" }
      }.to have_rejected_connection
    end

    it "rejects a read-only token (the terminal channel runs commands)" do
      token_record.update!(scope: "read")
      expect {
        connect headers: { "Authorization" => "Bearer #{plain_token}" }
      }.to have_rejected_connection
    end

    it "touches last_used_at on successful auth" do
      freeze_time do
        connect headers: { "Authorization" => "Bearer #{plain_token}" }
        expect(token_record.reload.last_used_at.to_i).to be_within(2).of(Time.current.to_i)
      end
    end
  end

  describe "Warden cookie path" do
    let(:warden_with_user) do
      u = user
      Object.new.tap { |w| w.define_singleton_method(:user) { u } }
    end
    let(:warden_without_user) do
      Object.new.tap { |w| w.define_singleton_method(:user) { nil } }
    end

    it "connects when warden has a user" do
      connect env: { "warden" => warden_with_user }
      expect(connection.current_user).to eq(user)
    end

    it "rejects when warden has no user" do
      expect {
        connect env: { "warden" => warden_without_user }
      }.to have_rejected_connection
    end
  end
end
