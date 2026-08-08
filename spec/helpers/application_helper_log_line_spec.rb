# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, "log line level classification" do
  describe "#log_line_level" do
    it "tags error / fatal / panic lines as error" do
      expect(helper.log_line_level("[2026-05-16 12:00:00] ERROR something broke")).to eq("error")
      expect(helper.log_line_level("FATAL: db connection lost")).to eq("error")
      expect(helper.log_line_level("kernel panic")).to eq("error")
    end

    it "tags warn lines as warn" do
      expect(helper.log_line_level("WARN slow query 1500ms")).to eq("warn")
      expect(helper.log_line_level("[warning] deprecated API")).to eq("warn")
    end

    it "tags nginx lines as nginx" do
      expect(helper.log_line_level("nginx: GET / 200")).to eq("nginx")
    end

    it "falls back to info for everything else" do
      expect(helper.log_line_level("Started GET / for 127.0.0.1")).to eq("info")
      expect(helper.log_line_level("")).to eq("info")
    end
  end

  describe "#log_line_class" do
    it "returns the right tailwind class per level" do
      expect(helper.log_line_class("error happened")).to eq("text-red-400")
      expect(helper.log_line_class("warn here")).to eq("text-yellow-500")
      expect(helper.log_line_class("nginx access log")).to eq("text-blue-400")
      expect(helper.log_line_class("plain info")).to eq("text-gray-400")
    end
  end
end
