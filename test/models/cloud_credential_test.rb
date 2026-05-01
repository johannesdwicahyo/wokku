require "test_helper"

class CloudCredentialTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid with provider, api_key, and team" do
    cred = CloudCredential.new(provider: "hetzner", api_key: "somekey", team: teams(:one))
    assert cred.valid?
  end

  test "invalid without provider" do
    cred = CloudCredential.new(api_key: "somekey", team: teams(:one))
    assert_not cred.valid?
    assert_includes cred.errors[:provider], "can't be blank"
  end

  test "invalid with unknown provider" do
    cred = CloudCredential.new(provider: "aws", api_key: "somekey", team: teams(:one))
    assert_not cred.valid?
    assert_includes cred.errors[:provider], "is not included in the list"
  end

  test "invalid without api_key" do
    cred = CloudCredential.new(provider: "hetzner", team: teams(:one))
    assert_not cred.valid?
    assert_includes cred.errors[:api_key], "can't be blank"
  end

  test "valid for all supported providers" do
    %w[hetzner vultr digitalocean linode].each do |provider|
      cred = CloudCredential.new(provider: provider, api_key: "key-#{provider}", team: teams(:one))
      assert cred.valid?, "expected #{provider} to be a valid provider"
    end
  end

  # --- Associations ---

  test "belongs to team" do
    cred = cloud_credentials(:one)
    assert_equal teams(:one), cred.team
  end

  # --- PROVIDERS constant ---

  test "PROVIDERS constant contains all four providers" do
    assert_equal %w[hetzner vultr digitalocean linode].sort, CloudCredential::PROVIDERS.keys.sort
  end

  test "PROVIDERS constant includes name and api_base for each provider" do
    CloudCredential::PROVIDERS.each do |key, info|
      assert info[:name].present?, "#{key} is missing :name"
      assert info[:api_base].present?, "#{key} is missing :api_base"
    end
  end
end
