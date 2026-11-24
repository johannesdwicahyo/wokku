# frozen_string_literal: true

require "spec_helper"

RSpec.describe "design tokens" do
  root = Pathname.new(File.expand_path("../..", __dir__))
  css = File.read(root.join("app/assets/tailwind/wokku.css"))

  it "self-hosts Geist and Geist Mono" do
    %w[geist-300 geist-400 geist-500 geist-600 geist-mono-400 geist-mono-500].each do |f|
      expect(css).to include(%(url("/fonts/#{f}.woff2")))
      expect(root.join("harness/public/fonts/#{f}.woff2")).to exist
    end
  end

  it "uses Geist for every sans token and Geist Mono for mono" do
    %w[sans body label headline sans-brutal].each do |t|
      expect(css).to match(/--font-#{t}:\s*"Geist",\s*"Inter",\s*system-ui,\s*sans-serif;/)
    end
    %w[mono mono-brutal].each do |t|
      expect(css).to match(/--font-#{t}:\s*"Geist Mono",\s*ui-monospace,\s*monospace;/)
    end
  end
end
