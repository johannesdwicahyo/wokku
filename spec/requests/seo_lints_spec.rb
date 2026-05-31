require "rails_helper"
require "nokogiri"

# Phase 1 task 24 — SEO lints enforced as request specs.
#
# Two hard rules per the spec §6 SEO requirements:
#   1. Exactly one <h1> per public page (semantic HTML + search ranking)
#   2. Every <img> has an alt attribute (accessibility + ranking).
#      Empty alt="" is permitted — it's the W3C-blessed way to mark a
#      decorative image so screen readers skip it. The hard rule is the
#      attribute MUST be present; missing alt is what hurts accessibility.
#
# These specs are the regression bar: if a future PR breaks either rule
# on a public page, CI fails. The /lp/* per-spike pages are included so
# the paid-ad funnel doesn't ship with accessibility regressions either,
# even though they're noindex'd.

RSpec.describe "SEO lints — exactly one h1 + alt on every img", type: :request do
  PUBLIC_PATHS_TO_LINT = %w[
    /
    /pricing
    /faq
    /lp/zero-ops
    /lp/ai-native
    /lp/flat-price
    /lp/one-click-apps
  ].freeze

  before do
    %w[free solo pro team].each do |k|
      Plan.find_or_create_by!(key: k) { |p| p.name = k.capitalize }
    end
    Plan.find_by(key: "free").update!(price_usd_cents: 0,    price_idr: 0)
    Plan.find_by(key: "solo").update!(price_usd_cents: 500,  price_idr: 75_000)
    Plan.find_by(key: "pro").update!(price_usd_cents: 1500,  price_idr: 225_000)
    Plan.find_by(key: "team").update!(price_usd_cents: 5000, price_idr: 750_000)
  end

  PUBLIC_PATHS_TO_LINT.each do |path|
    context "GET #{path}" do
      let(:doc) do
        get path
        expect(response).to have_http_status(:ok),
          "expected #{path} to render 200, got #{response.status}"
        Nokogiri::HTML5(response.body)
      end

      it "has exactly one <h1>" do
        h1s = doc.css("h1")
        sample = h1s.map { |h| h.text.strip.gsub(/\s+/, " ").slice(0, 60) }
        expect(h1s.count).to eq(1),
          "#{path}: expected exactly 1 <h1>, found #{h1s.count}: #{sample.inspect}"
      end

      it "every <img> has an alt attribute (empty alt='' allowed for decorative)" do
        bad = doc.css("img").reject { |img| img.attributes.key?("alt") }
        sample = bad.map { |img| img["src"].to_s.slice(0, 60) }
        expect(bad).to be_empty,
          "#{path}: #{bad.count} <img> with NO alt attribute (use alt='' for decorative): #{sample.inspect}"
      end
    end
  end
end
