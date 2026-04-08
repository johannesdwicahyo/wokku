module DocsHelper
  def docs_active?(path)
    @path == path
  end

  def docs_section_active?(section)
    section["items"].any? { |item| item["path"] == @path }
  end

  def docs_page_title
    item = nil
    @sidebar.each do |section|
      section["items"].each do |i|
        item = i if i["path"] == @path
      end
    end
    item ? "#{item['title']} - Wokku Docs" : "Documentation - Wokku"
  end
end
