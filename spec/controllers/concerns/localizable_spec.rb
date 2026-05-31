require "rails_helper"

# Localizable is included in ApplicationController, which covers all dashboard routes.
# We test it through the dashboard login redirect (no auth needed to hit a controller
# that runs before_action :set_locale).
RSpec.describe Localizable, type: :request do
  before { I18n.locale = I18n.default_locale }
  after  { I18n.locale = I18n.default_locale }

  it "defaults to I18n.default_locale when no hint is given" do
    get root_path
    expect(I18n.locale).to eq(I18n.default_locale)
  end

  it "switches to :id when the locale param is 'id'" do
    get root_path, params: { locale: "id" }
    expect(I18n.locale).to eq(:id)
  end

  it "switches to :en when the locale param is 'en'" do
    get root_path, params: { locale: "en" }
    expect(I18n.locale).to eq(:en)
  end

  it "ignores an unknown locale param and stays at the default" do
    get root_path, params: { locale: "fr" }
    expect(I18n.locale).to eq(I18n.default_locale)
  end

  it "switches locale based on the Accept-Language header" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "id,en;q=0.9" }
    expect(I18n.locale).to eq(:id)
  end

  it "keeps the default when Accept-Language requests an unsupported locale" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "fr,de;q=0.9" }
    expect(I18n.locale).to eq(I18n.default_locale)
  end

  it "gives precedence to the locale param over Accept-Language" do
    get root_path,
        params: { locale: "en" },
        headers: { "HTTP_ACCEPT_LANGUAGE" => "id" }
    expect(I18n.locale).to eq(:en)
  end
end
