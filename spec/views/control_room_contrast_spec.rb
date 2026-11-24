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

  {
    "app/views/dashboard/workspaces/show.html.erb" => 3,
    "app/views/dashboard/workspaces/_form.html.erb" => 1,
    "app/components/organisms/resource_builder_component.html.erb" => 1
  }.each do |path, count|
    it "#{path} form fields use a 3:1 border" do
      fields = src(path).scan(/<%=\s*(?:f\.)?(?:\w+_field(?:_tag)?|select_tag|text_area)\b.*?%>|<input\b[^>]*>/m)
                        .reject { |t| t.include?('type="range"') || t.include?("hidden") }
      expect(fields.size).to be >= count
      fields.each { |t| expect(t).not_to match(/border-(rule|line)(-soft)?\b/) }
    end
  end

  it "breadcrumb separators are readable", type: :component do
    render_inline(Molecules::BreadcrumbComponent.new(crumbs: [ [ "Apps", "/a" ], [ "demo", nil ] ]))
    expect(page).to have_css("span.text-dim[aria-hidden='true']", text: "/")
  end
end
