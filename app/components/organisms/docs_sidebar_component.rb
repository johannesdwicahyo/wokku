module Organisms
  # Renders the docs sidebar from a YAML structure (loaded by
  # DocsController from `docs/sidebar.<locale>.yml`). The section
  # containing the active page expands; siblings stay collapsed.
  #
  # sidebar:     Array of { "title", "icon", "items" => [{ "title", "path" }, ...] }
  # active_path: the current page path (e.g. "getting-started/sign-up")
  class DocsSidebarComponent < ApplicationComponent
    def initialize(sidebar:, active_path:)
      @sidebar = sidebar
      @active_path = active_path.to_s
    end
    attr_reader :sidebar, :active_path

    def section_open?(section)
      section["items"].any? { |item| item["path"] == active_path }
    end

    def active?(item)
      item["path"] == active_path
    end
  end
end
