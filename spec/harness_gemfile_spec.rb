require "rails_helper"

# The self-host image installs harness/Gemfile, not the engine's Gemfile, so a
# gem that the engine requires lazily must be listed there as well. Otherwise
# the code works in specs and fails in production.
RSpec.describe "harness/Gemfile.lock" do
  let(:lock) { Bundler::LockfileParser.new(File.read(File.expand_path("../harness/Gemfile.lock", __dir__))) }

  it "ships aws-sdk-s3 for self-host backups (BackupDestination)" do
    expect(lock.specs.map(&:name)).to include("aws-sdk-s3")
  end
end
