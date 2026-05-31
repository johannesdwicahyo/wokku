require "rails_helper"

RSpec.describe CloudCredential do
  describe "validations" do
    it "is valid with provider, api_key, and team" do
      cred = CloudCredential.new(provider: "hetzner", api_key: "somekey", team: teams(:one))
      expect(cred).to be_valid
    end

    it "is invalid without provider" do
      cred = CloudCredential.new(api_key: "somekey", team: teams(:one))
      expect(cred).not_to be_valid
      expect(cred.errors[:provider]).to include("can't be blank")
    end

    it "is invalid with unknown provider" do
      cred = CloudCredential.new(provider: "aws", api_key: "somekey", team: teams(:one))
      expect(cred).not_to be_valid
      expect(cred.errors[:provider]).to include("is not included in the list")
    end

    it "is invalid without api_key" do
      cred = CloudCredential.new(provider: "hetzner", team: teams(:one))
      expect(cred).not_to be_valid
      expect(cred.errors[:api_key]).to include("can't be blank")
    end

    it "is valid for all supported providers" do
      %w[hetzner vultr digitalocean linode].each do |provider|
        cred = CloudCredential.new(provider: provider, api_key: "key-#{provider}", team: teams(:one))
        expect(cred).to be_valid, "expected #{provider} to be a valid provider"
      end
    end
  end

  it "belongs to team" do
    cred = cloud_credentials(:one)
    expect(cred.team).to eq(teams(:one))
  end

  describe "PROVIDERS constant" do
    it "contains all four providers" do
      expect(CloudCredential::PROVIDERS.keys.sort).to eq(%w[hetzner vultr digitalocean linode].sort)
    end

    it "includes name and api_base for each provider" do
      CloudCredential::PROVIDERS.each do |key, info|
        expect(info[:name]).to be_present, "#{key} is missing :name"
        expect(info[:api_base]).to be_present, "#{key} is missing :api_base"
      end
    end
  end
end
