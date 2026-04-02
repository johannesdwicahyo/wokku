require "test_helper"

# Localizable is included in ApplicationController, which covers all dashboard routes.
# We test it through the dashboard login redirect (no auth needed to hit a controller
# that runs before_action :set_locale).
class LocalizableTest < ActionDispatch::IntegrationTest
  setup do
    # Reset to default locale before each test
    I18n.locale = I18n.default_locale
  end

  teardown do
    I18n.locale = I18n.default_locale
  end

  test "locale defaults to I18n.default_locale when no hint given" do
    get root_path
    assert_equal I18n.default_locale, I18n.locale
  end

  test "locale param switches locale to :id" do
    get root_path, params: { locale: "id" }
    assert_equal :id, I18n.locale
  end

  test "locale param switches locale to :en" do
    get root_path, params: { locale: "en" }
    assert_equal :en, I18n.locale
  end

  test "unknown locale param is ignored and locale stays at default" do
    get root_path, params: { locale: "fr" }
    assert_equal I18n.default_locale, I18n.locale
  end

  test "Accept-Language header switches locale" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "id,en;q=0.9" }
    assert_equal :id, I18n.locale
  end

  test "Accept-Language header for unsupported locale keeps default" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "fr,de;q=0.9" }
    assert_equal I18n.default_locale, I18n.locale
  end

  test "locale param takes precedence over Accept-Language header" do
    get root_path,
        params: { locale: "en" },
        headers: { "HTTP_ACCEPT_LANGUAGE" => "id" }
    assert_equal :en, I18n.locale
  end
end
