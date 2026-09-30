# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps::Addons", type: :request do
  include Devise::Test::IntegrationHelpers

  # users(:one) is a regular member with team membership in teams(:one).
  # app_records(:one) belongs to teams(:one) — so users(:one) is authorised.
  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }

  around do |ex|
    orig = ENV["BUNDLE_V2_ENABLED"]
    ENV["BUNDLE_V2_ENABLED"] = "true"
    ex.run
  ensure
    ENV["BUNDLE_V2_ENABLED"] = orig
  end

  before { sign_in user }

  describe "POST upgrade_to_dedicated" do
    let(:url) { "/dashboard/apps/#{app_record.id}/addons/postgres/upgrade" }

    context "when DatabaseServiceUpgrade succeeds" do
      before do
        dedicated = instance_double(DatabaseService, id: SecureRandom.uuid)
        allow(DatabaseServiceUpgrade).to receive(:call).with(app: app_record, user: user).and_return(dedicated)
      end

      it "redirects to the app settings tab with a notice" do
        post url
        expect(response).to redirect_to(dashboard_app_domains_path(app_record))
        follow_redirect!
        expect(flash[:notice]).to match(/Upgrading/i)
      end
    end

    # Review #3b: a builder capacity refusal must read as capacity, not as
    # OverLimit's generic "over your account limit" UI_MESSAGE.
    context "when the builder refuses on capacity (UpgradeError::OverLimit)" do
      before do
        allow(DatabaseServiceUpgrade).to receive(:call)
          .and_raise(UpgradeError::OverLimit, "Server capacity is full — try a smaller size.")
      end

      it "shows the real refusal message" do
        post url
        expect(flash[:alert]).to eq("Server capacity is full — try a smaller size.")
      end
    end

    context "when pre-flight raises UpgradeError::NoFreeSlots" do
      before do
        allow(DatabaseServiceUpgrade).to receive(:call).and_raise(UpgradeError::NoFreeSlots)
      end

      it "redirects back with the UI_MESSAGE in flash[:alert]" do
        post url
        expect(response).to redirect_to(dashboard_app_domains_path(app_record))
        expect(flash[:alert]).to include("dedicated Postgres slots")
      end
    end

    context "when user does not belong to the app's team" do
      # users(:two) has team membership only in teams(:two);
      # app_records(:one) belongs to teams(:one) — so they're denied.
      before { sign_in users(:two) }

      it "is denied (302 redirect, 403, or 404)" do
        post url
        expect([ 302, 403, 404 ]).to include(response.status)
      end
    end
  end

  describe "POST upgrade_redis_to_dedicated" do
    let(:url) { "/dashboard/apps/#{app_record.id}/addons/redis/upgrade" }

    context "when DatabaseServiceUpgrade succeeds" do
      before do
        dedicated = instance_double(DatabaseService, id: SecureRandom.uuid)
        allow(DatabaseServiceUpgrade).to receive(:call).with(app: app_record, user: user, engine: "redis").and_return(dedicated)
      end

      it "redirects to the app settings tab with a notice" do
        post url
        expect(response).to redirect_to(dashboard_app_domains_path(app_record))
        follow_redirect!
        expect(flash[:notice]).to match(/Upgrading/i)
      end
    end

    context "when pre-flight raises UpgradeError::NoFreeSlots" do
      before do
        allow(DatabaseServiceUpgrade).to receive(:call).with(app: app_record, user: user, engine: "redis").and_raise(UpgradeError::NoFreeSlots)
      end

      it "redirects back with the UI_MESSAGE in flash[:alert]" do
        post url
        expect(response).to redirect_to(dashboard_app_domains_path(app_record))
        expect(flash[:alert]).to include("dedicated Postgres slots")
      end
    end

    context "when user does not belong to the app's team" do
      before { sign_in users(:two) }

      it "is denied (302 redirect, 403, or 404)" do
        post url
        expect([ 302, 403, 404 ]).to include(response.status)
      end
    end
  end
end
