# frozen_string_literal: true

require "rails_helper"

RSpec.describe ControlPlaneBackupJob, type: :job do
  it "no-ops with a warning when required env is not set" do
    described_class::REQUIRED_ENV.each { |k| ENV.delete(k) }
    expect { described_class.new.perform }.not_to raise_error
  end
end
