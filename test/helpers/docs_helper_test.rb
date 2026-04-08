require "test_helper"

class DocsHelperTest < ActionView::TestCase
  setup do
    @sidebar = YAML.load_file(Rails.root.join("docs/sidebar.yml"))
    @path = "getting-started/sign-up"
  end

  test "docs_active? returns true for current path" do
    assert docs_active?("getting-started/sign-up")
  end

  test "docs_active? returns false for other path" do
    refute docs_active?("apps/create")
  end

  test "docs_section_active? returns true when section contains current path" do
    section = @sidebar.find { |s| s["title"] == "Getting Started" }
    assert docs_section_active?(section)
  end

  test "docs_section_active? returns false for other section" do
    section = @sidebar.find { |s| s["title"] == "Apps" }
    refute docs_section_active?(section)
  end

  test "docs_page_title includes page title" do
    assert_match(/Sign Up/, docs_page_title)
    assert_match(/Wokku Docs/, docs_page_title)
  end
end
