require "rails_helper"

RSpec.describe DocsHelper, type: :helper do
  let(:sidebar) { YAML.load_file(Rails.root.join("docs/sidebar.yml")) }

  before do
    helper.instance_variable_set(:@path, "getting-started/sign-up")
    helper.instance_variable_set(:@sidebar, sidebar)
  end

  describe "#docs_active?" do
    it "returns true for current path" do
      expect(helper.docs_active?("getting-started/sign-up")).to be true
    end

    it "returns false for another path" do
      expect(helper.docs_active?("apps/create")).to be false
    end
  end

  describe "#docs_section_active?" do
    it "returns true when section contains current path" do
      section = sidebar.find { |s| s["title"] == "Getting Started" }
      expect(helper.docs_section_active?(section)).to be true
    end

    it "returns false for another section" do
      section = sidebar.find { |s| s["title"] == "Apps" }
      expect(helper.docs_section_active?(section)).to be false
    end
  end

  describe "#docs_page_title" do
    it "includes page title and Wokku Docs" do
      expect(helper.docs_page_title).to match(/Sign Up/)
      expect(helper.docs_page_title).to match(/Wokku Docs/)
    end
  end
end
