require "rails_helper"

RSpec.describe EeHelper, type: :helper do
  describe "#ee_feature" do
    after { Wokku.instance_variable_set(:@ee, nil) }

    it "returns nil when not in EE mode" do
      Wokku.instance_variable_set(:@ee, false)
      expect(helper.ee_feature("some/partial")).to be_nil
    end

    it "rescues render errors and returns nil in EE mode" do
      Wokku.instance_variable_set(:@ee, true)
      # render will raise because partial doesn't exist; ee_feature rescues
      expect(helper.ee_feature("nonexistent/partial_that_does_not_exist")).to be_nil
    end
  end
end
