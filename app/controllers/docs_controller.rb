class DocsController < ApplicationController
  layout "docs"

  def show
    @path = params[:path] || "getting-started/sign-up"
    @sidebar = load_sidebar
    @content = render_doc(@path)
    @toc = extract_toc(@content)
    @prev_page, @next_page = find_prev_next(@path)
  end

  private

  def load_sidebar
    @_sidebar ||= YAML.load_file(Rails.root.join("docs/sidebar.yml"))
  end

  def render_doc(path)
    file = Rails.root.join("docs/content/#{path}.md")
    raise ActiveRecord::RecordNotFound unless file.exist?

    raw = file.read
    processed = preprocess_tabs(raw)
    html = render_markdown(processed)
    add_heading_anchors(html)
  end

  def render_markdown(text)
    html = Commonmarker.to_html(text, options: {
      parse: { smart: true },
      render: { unsafe: true }
    })
    highlight_code_blocks(html)
  end

  def highlight_code_blocks(html)
    formatter = Rouge::Formatters::HTML.new
    html.gsub(%r{<pre><code class="language-(\w+)">(.*?)</code></pre>}m) do
      lang = $1
      code = CGI.unescapeHTML($2)
      lexer = Rouge::Lexer.find(lang) || Rouge::Lexers::PlainText.new
      highlighted = formatter.format(lexer.lex(code))
      %(<div class="docs-code-block"><div class="docs-code-lang">#{lang}</div><pre><code>#{highlighted}</code></pre></div>)
    end
  end

  def preprocess_tabs(content)
    content.gsub(/:::tabs\n(.*?):::/m) do
      tabs_content = $1
      channels = tabs_content.scan(/::(\S+)\n(.*?)(?=::\S|\z)/m)

      tab_buttons = channels.map do |key, _|
        label = tab_label(key)
        %(<button type="button" class="docs-tab-btn" data-docs-tabs-target="tab" data-tab="#{key}" data-action="click->docs-tabs#switch">#{label}</button>)
      end.join("\n")

      tab_panels = channels.map do |key, body|
        rendered = render_markdown(body.strip)
        %(<div class="docs-tab-panel" data-tab="#{key}">#{rendered}</div>)
      end.join("\n")

      <<~HTML
        <div class="docs-tabs" data-controller="docs-tabs">
          <div class="docs-tab-bar">#{tab_buttons}</div>
          #{tab_panels}
        </div>
      HTML
    end
  end

  def tab_label(key)
    {
      "web-ui" => "Web UI",
      "cli" => "CLI",
      "api" => "API",
      "mcp" => "Claude Code",
      "mobile" => "Mobile"
    }.fetch(key, key.titleize)
  end

  def add_heading_anchors(html)
    html.gsub(/<(h[23])[^>]*>(.*?)<\/\1>/i) do
      tag = $1
      text = $2.gsub(/<[^>]+>/, "")
      id = text.downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-")
      %(<#{tag} id="#{id}"><a href="##{id}" class="docs-anchor">#</a>#{$2}</#{tag}>)
    end
  end

  def extract_toc(html)
    html.scan(/<(h[23]) id="([^"]+)"[^>]*>.*?>(.*?)<\/\1>/i).map do |tag, id, text|
      { level: tag == "h2" ? 2 : 3, id: id, text: text.gsub(/<[^>]+>/, "") }
    end
  end

  def find_prev_next(path)
    flat = load_sidebar.flat_map { |section| section["items"].map { |item| item["path"] } }
    idx = flat.index(path)
    return [nil, nil] unless idx

    prev_path = idx > 0 ? flat[idx - 1] : nil
    next_path = idx < flat.length - 1 ? flat[idx + 1] : nil

    prev_item = prev_path ? find_sidebar_item(prev_path) : nil
    next_item = next_path ? find_sidebar_item(next_path) : nil

    [prev_item, next_item]
  end

  def find_sidebar_item(path)
    load_sidebar.each do |section|
      section["items"].each do |item|
        return { "title" => item["title"], "path" => item["path"] } if item["path"] == path
      end
    end
    nil
  end
end
