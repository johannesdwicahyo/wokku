require "rails_helper"

RSpec.describe ApiErrors do
  it "has a complete entry for every code" do
    described_class::CATALOG.each do |code, entry|
      expect(entry).to include(:status, :message, :hint, :retryable), "incomplete: #{code}"
    end
  end

  it "builds the standard payload" do
    payload = described_class.payload(:deploy_lock_held)
    expect(payload).to eq(
      error: "A deploy is already in progress for this app",
      error_code: "deploy_lock_held",
      hint: "Wait for the current deploy to finish, then retry. If it never finishes, run wokku doctor.",
      retryable: true
    )
  end

  it "lets callers override the human message and attach details" do
    payload = described_class.payload(:validation_failed, message: "Name is invalid", details: [ "Name is invalid" ])
    expect(payload[:error]).to eq("Name is invalid")
    expect(payload[:details]).to eq([ "Name is invalid" ])
    expect(payload[:errors]).to eq([ "Name is invalid" ]) # legacy alias
  end

  describe ".from_service_code" do
    {
      dokku_error: :dokku_command_failed,
      container_not_found: :app_not_running,
      name_taken: :already_exists,
      invalid_name: :invalid_params,
      invalid_email: :invalid_params,
      invalid: :invalid_params,
      no_ssh_key: :validation_failed,
      no_postgres: :validation_failed,
      transfer_pending: :already_exists
    }.each do |service_code, api_code|
      it "maps #{service_code.inspect} to #{api_code.inspect}" do
        expect(described_class.from_service_code(service_code)).to eq(api_code)
      end
    end

    it "falls back to :invalid_params for unmapped codes" do
      expect(described_class.from_service_code(:recipient_missing)).to eq(:invalid_params)
      expect(described_class.from_service_code(:error)).to eq(:invalid_params)
    end
  end

  # Track B Phase B2: git-receive error catalog
  %w[deploy_in_progress ref_not_deployable archive_failed].each do |code|
    it "defines #{code}" do
      entry = described_class::CATALOG[code.to_sym]
      expect(entry).to be_present, "catalog is missing #{code}"
      expect(entry[:hint]).to be_present
    end
  end
end
