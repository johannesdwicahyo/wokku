# frozen_string_literal: true

require "rails_helper"

RSpec.describe "object_storage_pricing_note seam", type: :request do
  include Devise::Test::IntegrationHelpers

  after do
    Wokku.config.object_storage_pricing_note = nil
    Wokku.config.addons_index_sections = nil
  end

  let(:bucket) { create(:object_storage_bucket) }
  let(:note) { "Plans from Rp 1 <b>x</b>" }

  def card_text = ApplicationController.render(Molecules::ObjectStorageCardComponent.new(bucket: bucket), layout: false)

  def section_html
    Wokku.config.addons_index_sections = ->(_view, _team) {
      [ { partial: "dashboard/object_storages/section", locals: { app: app_records(:one) } } ]
    }
    sign_in users(:one)
    get "/dashboard/addons"
    response.body
  end

  it "defaults to nil" do
    expect(Wokku.config.object_storage_pricing_note.call(bucket.team)).to be_nil
  end

  it "shows no price text by default in card, section and API json" do
    expect(card_text).not_to match(/Rp|GB free/)
    expect(section_html).not_to match(/Rp|GB free/)
    expect(bucket.as_api_json(reveal: false)[:pricing_note]).to be_nil
  end

  context "with a configured note" do
    before { Wokku.config.object_storage_pricing_note = ->(_team) { note } }

    it "appends it, escaped, to the card and section" do
      expect(card_text).to include(ERB::Util.h(note))
      expect(card_text).not_to include("<b>x</b>")
      expect(section_html).to include(ERB::Util.h(note))
    end

    it "includes it in the API json" do
      expect(bucket.as_api_json(reveal: false)[:pricing_note]).to eq(note)
    end

    it "shows it on the usage page" do
      allow(Wokku).to receive(:cloud?).and_return(true)
      allow(Wokku.config).to receive(:object_storage?).and_return(true)
      user = users(:one)
      create(:object_storage_bucket, app_record: nil, team: user.teams.first)
      sign_in user
      get dashboard_usage_path
      expect(response.body).to include(ERB::Util.h(note))
    end
  end

  it "usage page has no price text by default" do
    allow(Wokku).to receive(:cloud?).and_return(true)
    allow(Wokku.config).to receive(:object_storage?).and_return(true)
    user = users(:one)
    create(:object_storage_bucket, app_record: nil, team: user.teams.first)
    sign_in user
    get dashboard_usage_path
    expect(response.body).to include("S3-compatible")
    expect(response.body).not_to match(/GB free/)
  end
end
