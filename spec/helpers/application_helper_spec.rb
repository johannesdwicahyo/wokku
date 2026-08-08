require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#template_icon" do
    it "returns the correct emoji for known icon names" do
      expect(helper.template_icon("rails")).to eq("🛤️")
      expect(helper.template_icon("ruby")).to eq("💎")
      expect(helper.template_icon("node")).to eq("🟢")
      expect(helper.template_icon("python")).to eq("🐍")
      expect(helper.template_icon("go")).to eq("🔷")
      expect(helper.template_icon("docker")).to eq("🐳")
      expect(helper.template_icon("ai")).to eq("🤖")
    end

    it "returns the default box emoji for unknown icon names" do
      expect(helper.template_icon("unknown")).to eq("📦")
      expect(helper.template_icon("foobar")).to eq("📦")
      expect(helper.template_icon("")).to eq("📦")
    end

    it "accepts a symbol" do
      expect(helper.template_icon(:rails)).to eq("🛤️")
      expect(helper.template_icon(:unknown)).to eq("📦")
    end
  end

  describe "#log_line_class" do
    it "returns red for error lines" do
      expect(helper.log_line_class("ERROR: something broke")).to eq("text-red-400")
      expect(helper.log_line_class("fatal exception")).to eq("text-red-400")
      expect(helper.log_line_class("PANIC at the disco")).to eq("text-red-400")
      expect(helper.log_line_class("error in worker")).to eq("text-red-400")
    end

    it "returns yellow for warning lines" do
      expect(helper.log_line_class("WARN: disk space low")).to eq("text-yellow-500")
      expect(helper.log_line_class("warning: something is off")).to eq("text-yellow-500")
    end

    it "returns blue for nginx lines" do
      expect(helper.log_line_class("nginx: worker started")).to eq("text-blue-400")
      expect(helper.log_line_class("NGINX access log")).to eq("text-blue-400")
    end

    it "returns gray for ordinary lines" do
      expect(helper.log_line_class("app started on port 3000")).to eq("text-gray-400")
      expect(helper.log_line_class("info: all systems normal")).to eq("text-gray-400")
      expect(helper.log_line_class("")).to eq("text-gray-400")
    end
  end
end
