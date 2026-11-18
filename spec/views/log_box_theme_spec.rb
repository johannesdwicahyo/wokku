require "rails_helper"

# bg-ink flips to near-white in dark mode; the green-on-dark log boxes must
# keep a fixed dark background or their text becomes unreadable.
RSpec.describe "log boxes" do
  %w[app/views/dashboard/logs/_glance.html.erb app/views/dashboard/apps/frames/_panel_logs.html.erb].each do |path|
    it "#{path} keeps a fixed dark background in both themes" do
      src = File.read(File.expand_path("../../#{path}", __dir__))
      expect(src).to include("bg-[#171717] text-[#9DEE9D]")
      expect(src).not_to match(/bg-ink text-\[#9DEE9D\]/)
    end

    it "#{path} wraps long unspaced log lines inside the box" do
      src = File.read(File.expand_path("../../#{path}", __dir__))
      expect(src).to match(/bg-\[#171717\][^"]*\bmin-w-0\b[^"]*\bwrap-anywhere\b/)
    end
  end
end
