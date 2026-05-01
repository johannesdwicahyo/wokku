#!/usr/bin/env ruby
# Audit `turbo_frame_tag` blocks in app/views for inner navigations
# (link_to, button_to, form_with) that don't carry `data-turbo-frame: "_top"`
# and aren't targeting a same-id frame.
#
# Symptom of a missing _top: clicking a link/button inside a wrapped
# frame whose destination doesn't render the same frame id shows
# "Content missing" instead of navigating. See backlog entry
# 2026-04-30 for prior bugs (Change Plan in _resource_limits, Open/
# Retry/Destroy in _addon_card, Full Logs in _live_logs).
#
# Block-aware: Ruby block-openers (do, if, unless, case, each, begin,
# while, until) push generic depth; <% end %> pops it. Frames are
# tracked on a separate stack with the depth at which they opened, so
# closing an inner block doesn't fool us into thinking the frame is
# closed too — caught the live_logs false-negative on 2026-04-30.
#
# Usage:
#   bin/check_turbo_frames.rb              # exits 1 on findings
#   bin/check_turbo_frames.rb --quiet      # only print findings (no header)

require "pathname"

root = Pathname.new(__dir__).join("..", "app", "views").expand_path
quiet = ARGV.include?("--quiet")

# A line opens a Ruby block when it has any of these keywords *outside*
# strings/symbols and the line doesn't also close them on the same line
# (`if x; foo; end`). For ERB the heuristic is good enough — false
# positives just over-report depth, never under-report frames.
BLOCK_OPENERS = /\b(do|if|unless|case|each|begin|while|until)\b/
END_TAG = /^\s*<%-?\s*end\s*-?%>/

def block_opens(line)
  # Crude scan: count occurrences of openers outside ERB tags. We don't
  # try to be exact about modifier-if vs full-if — anything that can
  # introduce an `end` we count.
  count = 0
  count += 1 if line =~ /\bdo\b\s*(\|[^|]*\|)?\s*-?%>/         # do |x| %>
  count += 1 if line =~ /<%[-=]?\s*if\b/ && line !~ /<%[-=]?\s*if\b.*\bend\s*-?%>/
  count += 1 if line =~ /<%[-=]?\s*unless\b/ && line !~ /<%[-=]?\s*unless\b.*\bend\s*-?%>/
  count += 1 if line =~ /<%[-=]?\s*case\b/
  count += 1 if line =~ /<%[-=]?\s*begin\b/
  count += 1 if line =~ /\.each\b.*\bdo\b/  # already counted by `do` rule above; gate to avoid double
  # The .each rule double-counts with the `do` rule — back it out.
  count -= 1 if line =~ /\.each\b.*\bdo\b/
  count
end

findings = []

root.glob("**/*.erb").each do |file|
  src = file.read
  depth = 0
  # Stack of [frame_id, opened_at_depth, opened_line]. A frame closes
  # when depth drops back to opened_at_depth (the matching <% end %>).
  frame_stack = []

  src.lines.each_with_index do |line, idx|
    line_no = idx + 1

    # Detect `turbo_frame_tag "id" ... do %>` opens BEFORE we count the
    # block-open it implies, so we record the right opened_at_depth.
    if line =~ /turbo_frame_tag\s+["']?([\w-]+)["']?.*\bdo\b/
      frame_stack << { id: Regexp.last_match(1), opened_at: depth, line: line_no }
    end

    # Detect `turbo_frame_tag` rendered as a self-closing partial source
    # (`turbo_frame_tag "id", src: ...`) — these don't open a Ruby block,
    # so they don't matter for inner-link detection.

    opens = block_opens(line)
    depth += opens
    if line =~ END_TAG
      depth -= 1 if depth.positive?
      # If the frame's matching end just fired, pop it.
      frame_stack.pop while frame_stack.any? && frame_stack.last[:opened_at] >= depth + 1 - frame_stack.last[:opened_at] && false
      # The above guard is wrong; use the simple invariant: a frame is
      # still open while depth > frame.opened_at.
      frame_stack.pop while frame_stack.any? && depth <= frame_stack.last[:opened_at]
    end

    # Only check for inner navigations when we're inside at least one frame.
    next if frame_stack.empty?

    is_nav = line =~ /\b(link_to|button_to|form_with|form_for|button_tag|form_tag)\b/ ||
             line =~ /<a\s|<form\s/
    next unless is_nav

    has_top = line.include?(%(turbo_frame: "_top")) ||
              line.include?(%(turbo_frame: '_top')) ||
              line.include?(%(data-turbo-frame="_top")) ||
              line.include?(%(data-turbo-frame='_top'))
    next if has_top

    # Tolerated: link/form explicitly targets ITS OWN containing frame
    # (e.g. an api_tokens form posting back into the api_tokens frame).
    targets_own_frame = frame_stack.any? do |f|
      line.include?(%(turbo_frame: "#{f[:id]}")) || line.include?(%(turbo_frame: '#{f[:id]}'))
    end
    next if targets_own_frame

    findings << {
      file: file.relative_path_from(root.parent.parent),
      line: line_no,
      frame_id: frame_stack.last[:id],
      frame_line: frame_stack.last[:line],
      content: line.strip
    }
  end
end

if findings.empty?
  puts "OK — no turbo_frame_tag blocks contain unmarked inner navigations." unless quiet
  exit 0
end

unless quiet
  puts "Found #{findings.size} inner navigation(s) inside turbo_frame_tag blocks"
  puts "without `data: { turbo_frame: \"_top\" }`. Verify each destination"
  puts "renders the same frame id, or add the _top opt-out:"
  puts ""
end

findings.each do |f|
  puts "#{f[:file]}:#{f[:line]} (frame ##{f[:frame_id]} opened at line #{f[:frame_line]})"
  puts "  #{f[:content]}"
end

exit 1
