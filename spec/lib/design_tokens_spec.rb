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
    license = root.join("harness/public/fonts/LICENSE-Geist.txt")
    expect(license).to exist
    expect(license.read).to include("SIL OPEN FONT LICENSE")
  end

  it "uses Geist for every sans token and Geist Mono for mono" do
    %w[sans body label headline sans-brutal].each do |t|
      expect(css).to match(/--font-#{t}:\s*"Geist",\s*system-ui,\s*sans-serif;/)
    end
    %w[mono mono-brutal].each do |t|
      expect(css).to match(/--font-#{t}:\s*"Geist Mono",\s*ui-monospace,\s*monospace;/)
    end
  end

  it "has no Material You tokens" do
    expect(css).not_to match(/--color-(surface|on-surface|primary|on-primary|secondary|tertiary|error|on-error|outline|inverse|background|on-background)\b/)
    expect(css).not_to include("material-symbols")
  end

  it "has no legacy webfonts" do
    ["Inter Tight", "JetBrains Mono", '"Inter"', "/fonts/inter"].each { |t| expect(css).not_to include(t) }
    expect(root.join("harness/public/fonts").children.map { |c| c.basename.to_s }).not_to include(/inter|jetbrains/)
  end

  it "leaves no Material utility classes in app/" do
    re = /\b(bg|text|border)-(surface|on-surface|primary|on-primary|error|outline)\b|material-symbols/
    offenders = Dir[root.join("app/**/*")].reject { |f| f.include?("assets/builds") || !File.file?(f) }
                  .select { |f| File.read(f, encoding: "UTF-8").match?(re) rescue false }
    expect(offenders).to eq([])
  end

  it "does not paint the light meter squares transparent (unlayered CSS would beat bg-live/bg-ink)" do
    rule = css[/^\.wk-meter > span \{[^}]*\}/]
    expect(rule).to be_present
    expect(rule).not_to match(/background/)
  end

  it "delays the sidebar logo pulse so fast navigations never dim it" do
    rule = css[/^\.is-loading \.wk-logo-anim rect \{[^}]*\}/]
    expect(rule).not_to match(/animation-fill-mode|backwards|both/)
    expect(rule).to match(/calc\(700ms \+ var\(--i\) \* \.15s\)/)
  end

  it "is dark only" do
    expect(css).not_to include('[data-theme="dark"]')
    expect(css).to match(/:root\s*\{\s*color-scheme:\s*dark;/)
    {
      bg: "#050605", bg_deep: "#0B0D0B", paper: "#0B0D0B", ink: "#EEF1EC", ink_soft: "#C9CEC7",
      dim: "#8E968D", faint: "#8E968D", rule: "#1C1F1C", line: "#1C1F1C", rule_soft: "#141714",
      line_soft: "#141714", line_strong: "#2E332E", accent: "#22C55E", success: "#22C55E",
      info: "#22C55E", live: "#22C55E", live_hover: "#4ADE80", accent_soft: "#0F2A18",
      success_soft: "#0F2A18", info_soft: "#0F2A18", warn: "#FEC84B", warn_soft: "#2A220B",
      danger: "#F04438", hot: "#F04438", danger_soft: "#2A0F0D", hot_soft: "#2A0F0D",
      deploying: "#EEF1EC", dark_line: "#5D655C", bad_text: "#FDA29B"
    }.each do |name, hex|
      expect(css).to match(/--color-#{name.to_s.tr("_", "-")}:\s*#{Regexp.escape(hex)};/)
    end
    expect(css).to match(/--grid-dot:\s*rgba\(238,\s*241,\s*236,\s*0?\.06\)/)
    %w[brutal-sm brutal brutal-lg].each { |n| expect(css).to match(/--shadow-#{n}:\s*none/) }
  end
end
