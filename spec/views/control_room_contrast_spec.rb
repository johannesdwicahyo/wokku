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
  field = /<(?:input|select|textarea)\b(?:<%.*?%>|[^>"']|"[^"]*"|'[^']*')*>|<%=\s*(?:\w+\.)?(?:#{field_helpers})(?:_tag)?\b.*?%>/m
  # line / rule (and their -soft) are ~1.2:1; line-strong is not matched here.
  faint = /(?<![\w:-])border-(?:line(?:-strong)?|rule)(?:-soft)?(?![\w-])/

  line_of = ->(text, offset) { text[0, offset].count("\n") + 1 }

  it "no form field anywhere uses a faint (line/rule) border" do
    scanned = 0
    offenders = Dir["#{root}/app/{views,components}/**/*.erb", "#{root}/app/helpers/**/*.rb", "#{root}/app/javascript/**/*.js"].flat_map do |f|
      text = File.read(f)
      text.to_enum(:scan, field).filter_map do
        m = Regexp.last_match
        scanned += 1
        next if m[0].include?('type="hidden"') || !m[0].match?(faint)
        "#{f.delete_prefix("#{root}/")}:#{line_of.(text, m.begin(0))}"
      end
    end
    expect(scanned).to be > 50 # the pattern still finds the app's fields
    expect(offenders).to be_empty, "faint field borders (need 3:1, use border-dark-line or brighter; line-strong is ~1.6:1):\n#{offenders.join("\n")}"
  end

  it "no field-class local variable (input/inp/field/classes) carries a faint border" do
    assign = /^\s*(\w*(?:input|inp|field|classes)\w*)\s*=\s*"([^"]*)"/
    offenders = Dir["#{root}/app/{views,components}/**/*.erb", "#{root}/app/helpers/**/*.rb"].flat_map do |f|
      File.read(f).lines.each_with_index.filter_map do |l, i|
        m = l.match(assign) or next
        str = m[2]
        next unless str.match?(/\bpx-\d/) && str.match?(/\bpy-\d/) && str.match?(/rounded|w-full/) && str.match?(faint)
        next if m[1].match?(/label/)
        "#{f.delete_prefix("#{root}/")}:#{i + 1}"
      end
    end
    expect(offenders).to be_empty, "field class strings with faint borders:\n#{offenders.join("\n")}"
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

  # Task 6 guards ---------------------------------------------------------
  it "no view/component uses the loud near-white border-ink (variant-prefixed hover/focus/data states aside)" do
    # Allow-list: Atoms::ButtonComponent's :secondary hover state is deliberate.
    allow = %w[app/components/atoms/button_component.rb]
    offenders = Dir["#{root}/app/**/*.{erb,rb,js}"].flat_map do |f|
      rel = f.delete_prefix("#{root}/")
      next [] if allow.include?(rel)
      File.read(f).lines.each_with_index.filter_map do |l, i|
        "#{rel}:#{i + 1}" if l.match?(/(?<![\w:-])border(?:-[trblxy])?-ink(?![\w\/-])|border(?:-[trblxy])?-1\.5(?![\w.])/)
      end
    end
    expect(offenders).to be_empty, "loud borders (use border-line / border-line-strong):\n#{offenders.join("\n")}"
  end

  it "no ButtonComponent call re-creates a primary look through classes:" do
    offenders = Dir["#{root}/app/**/*.erb"].flat_map do |f|
      File.read(f).lines.each_with_index.filter_map do |l, i|
        next unless l.include?("ButtonComponent.new(") && l.include?("classes:")
        "#{f.delete_prefix("#{root}/")}:#{i + 1}" if l.match?(/classes:.*\bbg-(?:live|ink)\b/)
      end
    end
    expect(offenders).to be_empty
  end

  it "the primary recipe lives only in the button components" do
    allow = %w[app/components/atoms/button_component.rb app/components/atoms/optimistic_button_component.rb]
    offenders = Dir["#{root}/app/**/*.{erb,rb,js}"].flat_map do |f|
      rel = f.delete_prefix("#{root}/")
      next [] if allow.include?(rel)
      File.read(f).lines.each_with_index.filter_map { |l, i| "#{rel}:#{i + 1}" if l.include?("text-[#03140A]") && l.match?(/(?<![\w:-])bg-live(?![\w-])/) }
    end
    expect(offenders).to be_empty, "copies of the primary recipe (use Atoms::ButtonComponent):\n#{offenders.join("\n")}"
  end

  it "hand-rolled solid buttons use the live primary, not bg-ink" do
    offenders = Dir["#{root}/app/**/*.{erb,rb,js}"].flat_map do |f|
      File.read(f).lines.each_with_index.filter_map do |l, i|
        next unless l.match?(/bg-ink text-(?:bg|paper)|text-bg bg-ink/)
        next if l.match?(/'[^']*bg-ink|data-\[active|rounded-full|<div|flash_toast|lang_switch/)
        next unless l.match?(/f\.submit|<button|button_to|className/)
        "#{f.delete_prefix("#{root}/")}:#{i + 1}"
      end
    end
    expect(offenders).to be_empty, offenders.join("\n")
  end

  it "static error pages are dark-token, with no external fonts" do
    pages = Dir["#{root}/harness/public/*.html"]
    expect(pages.map { |f| File.basename(f) }).to include("400.html", "404.html", "406-unsupported-browser.html", "422.html", "500.html")
    pages.each do |f|
      html = File.read(f)
      expect(html).to include("#050605"), "#{f} lacks #050605"
      expect(html).not_to match(/fonts\.(googleapis|gstatic)/), "#{f} loads external fonts"
    end
  end

  it "the admin layout has no hard-coded English rail labels" do
    layout = src("app/views/layouts/admin.html.erb")
    expect(layout).not_to match(/label: "(?:Overview|Servers|Cloud credentials|Users|Settings|Jobs|← Back to dashboard)"/)
    expect(layout).not_to include('crumbs: [ "Admin" ]')
  end
end
