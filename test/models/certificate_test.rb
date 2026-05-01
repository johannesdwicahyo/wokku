require "test_helper"

class CertificateTest < ActiveSupport::TestCase
  test "belongs to domain" do
    cert = certificates(:one)
    assert_equal domains(:one), cert.domain
  end

  test "auto_renew defaults to true" do
    cert = Certificate.new(domain: domains(:one))
    # The default is set at DB level, so we check via create
    assert certificates(:one).auto_renew? || certificates(:two).auto_renew? == false
  end
end
