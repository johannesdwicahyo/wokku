require "rails_helper"

# Dark-only control room: text-bg is the page colour (invisible on dark
# boxes) and line/rule borders are ~1.2:1, too faint for a form field's
# edge (WCAG non-text contrast needs 3:1). These pins keep the fixes from
# the Task 6 sweep in place.
RSpec.describe "control-room contrast" do
  def src(path) = File.read(File.expand_path("../../#{path}", __dir__))

  it "log glance prefix is not drawn in the page colour" do
    expect(src("app/views/dashboard/logs/_glance.html.erb")).not_to match(/text-bg\b/)
  end

  root = File.expand_path("../..", __dir__)
  field_helpers = %w[text_field email_field password_field number_field select text_area
                     search_field url_field telephone_field file_field
                     date_field time_field datetime_field datetime_local_field month_field week_field
                     color_field collection_select date_select time_zone_select].join("|")
  # A raw control tag (quoted attrs may hold ">", e.g. data-action="input->x#y"),
  # or an ERB output tag calling a Rails field helper
  # (f.text_field, select_tag, text_area_tag, ...), up to its closing %>.
  field = /<(?:input|select|textarea)\b(?:[^>"']|"[^"]*"|'[^']*')*>|<%=\s*(?:\w+\.)?(?:#{field_helpers})(?:_tag)?\b.*?%>/m
  # line / rule (and their -soft) are ~1.2:1; line-strong is not matched here.
  faint = /\bborder-(?:line|rule)(?:-soft)?(?![\w-])/

  line_of = ->(text, offset) { text[0, offset].count("\n") + 1 }

  it "no form field anywhere uses a faint (line/rule) border" do
    scanned = 0
    offenders = Dir["#{root}/app/{views,components}/**/*.erb"].flat_map do |f|
      text = File.read(f)
      text.to_enum(:scan, field).filter_map do
        m = Regexp.last_match
        scanned += 1
        next if m[0].include?('type="hidden"') || !m[0].match?(faint)
        "#{f.delete_prefix("#{root}/")}:#{line_of.(text, m.begin(0))}"
      end
    end
    expect(scanned).to be > 50 # the pattern still finds the app's fields
    expect(offenders).to be_empty, "faint field borders (need 3:1, use border-dark-line or brighter):\n#{offenders.join("\n")}"
  end

  it "modal and drawer backdrops darken instead of washing the page with ink (near-white)" do
    # Any quoted string (double, single or template literal, ERB or JS) that
    # covers the viewport/parent must not tint with ink; variant-prefixed
    # classes (hover:bg-ink/90) are fine.
    overlay = /(?<![\w:-])(?:inset-0|inset-x-0|inset-y-0)(?![\w-])|(?<![\w:-])fixed(?![\w-])(?=.*(?<![\w:-])(?:w-full|h-full|size-full|w-screen|h-screen)(?![\w-]))|(?<![\w:-])(?:w-full|h-full|size-full|w-screen|h-screen)(?![\w-])(?=.*(?<![\w:-])fixed(?![\w-]))/m
    offenders = Dir["#{root}/app/{views,components,javascript}/**/*.{erb,js}"].flat_map do |f|
      text = File.read(f)
      text.to_enum(:scan, /"[^"]*"|'[^']*'|`[^`]*`/m).filter_map do
        m = Regexp.last_match
        next unless m[0].match?(%r{(?<![\w:-])bg-ink/\d+}) && m[0].match?(overlay)
        "#{f.delete_prefix("#{root}/")}:#{line_of.(text, m.begin(0))}"
      end
    end
    expect(offenders).to be_empty, "ink-tinted overlays:\n#{offenders.join("\n")}"
  end

  it "breadcrumb separators are readable", type: :component do
    render_inline(Molecules::BreadcrumbComponent.new(crumbs: [ [ "Apps", "/a" ], [ "demo", nil ] ]))
    expect(page).to have_css("span.text-dim[aria-hidden='true']", text: "/")
  end
end
