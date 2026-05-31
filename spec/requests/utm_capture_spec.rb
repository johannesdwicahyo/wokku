require "rails_helper"

# Phase 1 task 23 — UTM session capture verification.
#
# Pre-task gap: stash_utms was wired ONLY on PagesController#landing.
# /lp/:spike (Pages::LpController#show) didn't capture. This task
# extracted the logic to UtmCapturable concern + wired both
# controllers. These specs are the regression bar.

RSpec.describe "UTM session capture", type: :request do
  before do
    %w[free solo pro team].each do |k|
      Plan.find_or_create_by!(key: k) { |p| p.name = k.capitalize }
    end
  end

  describe "GET /" do
    it "captures utm_source/medium/campaign/term/content" do
      get "/?utm_source=meta&utm_medium=paid&utm_campaign=vbs-zero-ops&utm_term=ID&utm_content=img-3"
      expect(session[:utm]).to eq({
        "source"   => "meta",
        "medium"   => "paid",
        "campaign" => "vbs-zero-ops",
        "term"     => "ID",
        "content"  => "img-3"
      })
    end

    it "leaves session[:utm] unset when no utm_* params are present" do
      get "/"
      expect(session[:utm]).to be_nil
    end

    it "ignores non-canonical utm_* params" do
      get "/?utm_source=meta&utm_bogus=eviltracker"
      expect(session[:utm]).to eq({ "source" => "meta" })
    end

    it "caps each utm value at 64 chars (defense vs garbage referrers)" do
      get "/?utm_campaign=#{'A' * 200}"
      expect(session[:utm]["campaign"].length).to eq(64)
    end
  end

  describe "GET /lp/:spike (Pages::LpController)" do
    %w[zero-ops ai-native flat-price one-click-apps].each do |slug|
      it "[#{slug}] captures utm params into session" do
        get "/lp/#{slug}?utm_source=meta&utm_medium=paid&utm_campaign=vbs-#{slug}"
        expect(session[:utm]).to eq({
          "source"   => "meta",
          "medium"   => "paid",
          "campaign" => "vbs-#{slug}"
        })
      end
    end

    it "captures + persists across sub-navigation on /lp/* (session survives)" do
      get "/lp/zero-ops?utm_source=meta&utm_campaign=vbs-zero-ops"
      expect(session[:utm]).to eq({ "source" => "meta", "campaign" => "vbs-zero-ops" })

      # Next request without utm params → session retains the original capture
      get "/lp/zero-ops"
      expect(session[:utm]).to eq({ "source" => "meta", "campaign" => "vbs-zero-ops" })
    end
  end
end
