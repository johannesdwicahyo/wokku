require "rails_helper"

# Security assessment 2026-11-19, F-05: wokku.cloud enforces a CSP without
# 'unsafe-inline' for scripts, which blocks inline event handlers. Use a
# Stimulus action (data-action="change->auto-submit#submit") instead.
RSpec.describe "Views" do
  let(:handler) { /\bon(?:abort|blur|change|click|dblclick|error|focus|input|key(?:down|press|up)|load|mouse\w+|reset|scroll|select|submit|touch\w+)(?:\s*=\s*["']|:\s*["'])/ }

  it "have no inline event handlers" do
    files = Dir[Rails.root.join("..", "app", "{views,components}", "**", "*.{erb,rb}")]
    expect(files).not_to be_empty
    offenders = files.flat_map do |f|
      File.readlines(f).each_with_index.filter_map { |l, i| "#{f.sub(/.*\/app\//, 'app/')}:#{i + 1}" if l.match?(handler) }
    end
    expect(offenders).to be_empty, "inline handlers (use a Stimulus action): #{offenders.join(', ')}"
  end

  it "the scan catches both handler spellings" do
    expect(%(<img onerror="x()">)).to match(handler)
    expect(%(select_tag :a, [], onchange: "x()")).to match(handler)
    expect(%(data-action="change->auto-submit#submit")).not_to match(handler)
  end
end
