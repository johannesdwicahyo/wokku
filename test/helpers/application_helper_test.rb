require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "template_icon returns correct emoji for known icon names" do
    assert_equal "🛤️", template_icon("rails")
    assert_equal "💎", template_icon("ruby")
    assert_equal "🟢", template_icon("node")
    assert_equal "🐍", template_icon("python")
    assert_equal "🔷", template_icon("go")
    assert_equal "🐳", template_icon("docker")
    assert_equal "🤖", template_icon("ai")
  end

  test "template_icon returns default box emoji for unknown icon names" do
    assert_equal "📦", template_icon("unknown")
    assert_equal "📦", template_icon("foobar")
    assert_equal "📦", template_icon("")
  end

  test "template_icon accepts symbol" do
    assert_equal "🛤️", template_icon(:rails)
    assert_equal "📦", template_icon(:unknown)
  end

  test "log_line_class returns red for error lines" do
    assert_equal "text-red-400", log_line_class("ERROR: something broke")
    assert_equal "text-red-400", log_line_class("fatal exception")
    assert_equal "text-red-400", log_line_class("PANIC at the disco")
    assert_equal "text-red-400", log_line_class("error in worker")
  end

  test "log_line_class returns yellow for warning lines" do
    assert_equal "text-yellow-500", log_line_class("WARN: disk space low")
    assert_equal "text-yellow-500", log_line_class("warning: something is off")
  end

  test "log_line_class returns blue for nginx lines" do
    assert_equal "text-blue-400", log_line_class("nginx: worker started")
    assert_equal "text-blue-400", log_line_class("NGINX access log")
  end

  test "log_line_class returns gray for ordinary lines" do
    assert_equal "text-gray-400", log_line_class("app started on port 3000")
    assert_equal "text-gray-400", log_line_class("info: all systems normal")
    assert_equal "text-gray-400", log_line_class("")
  end
end
