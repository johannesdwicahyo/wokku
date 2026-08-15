# frozen_string_literal: true

require "rails_helper"

# The engine exports this concern for host apps to wire (include +
# before_action :stash_utms); nothing in the engine includes it, so test
# it directly on an anonymous controller.
RSpec.describe UtmCapturable, type: :controller do
  controller(ActionController::Base) do
    include UtmCapturable
    before_action :stash_utms

    def index
      head :ok
    end
  end

  it "stashes the canonical utm keys, length-capped" do
    get :index, params: { utm_source: "meta", utm_campaign: "x" * 100, utm_bogus: "nope" }
    expect(session[:utm]).to eq("source" => "meta", "campaign" => "x" * UtmCapturable::UTM_VALUE_LIMIT)
  end

  it "leaves the session untouched when no utm params are present" do
    get :index
    expect(session[:utm]).to be_nil
  end
end
