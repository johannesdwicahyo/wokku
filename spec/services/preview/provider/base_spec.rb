require "rails_helper"

RSpec.describe Preview::Provider::Base do
  describe ".parse" do
    it "raises NotImplementedError when called directly" do
      expect { described_class.parse({}) }.to raise_error(NotImplementedError, /must be implemented/)
    end
  end
end
