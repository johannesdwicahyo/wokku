module DocsHelper
  def docs_active?(path)
    @path == path
  end

  def docs_section_active?(section)
    section["items"].any? { |item| item["path"] == @path }
  end

  def docs_page_title
    item = nil
    Array(@sidebar).each do |section|
      section["items"].each do |i|
        item = i if i["path"] == @path
      end
    end
    title = (@doc_title.presence) || item&.dig("title")
    title ? "#{title} · Wokku Docs" : "Documentation · Wokku"
  end

  # Strip the first <h1> from rendered Markdown HTML so the article body
  # doesn't double the title that DocHeaderComponent already shows.
  def strip_first_h1(html)
    html.to_s.sub(/<h1[^>]*>.*?<\/h1>\s*/im, "")
  end
end
