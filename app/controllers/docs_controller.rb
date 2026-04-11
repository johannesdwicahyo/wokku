class DocsController < ApplicationController
  layout "docs"

  def show
    @path = params[:path] || "getting-started/sign-up"
    @sidebar = load_sidebar
    @content = render_doc(@path)
    @toc = extract_toc(@content)
    @prev_page, @next_page = find_prev_next(@path)
  end

  def search_index
    entries = []
    Dir.glob(Rails.root.join("docs/content/**/*.md")).each do |file|
      path = file.sub(Rails.root.join("docs/content/").to_s, "").sub(".md", "")
      content = File.read(file)
      title = content.match(/^# (.+)/)&.captures&.first || path.split("/").last.titleize
      headings = content.scan(/^## (.+)/).flatten
      body = content.gsub(/^#+ /, "").gsub(/```.*?```/m, "").gsub(/:::.*?:::/m, "").gsub(/::\S+/, "").strip[0..300]
      entries << { title: title, path: path, headings: headings, excerpt: body }
    end
    render json: entries
  end

  private

  def load_sidebar
    @_sidebar ||= YAML.load_file(Rails.root.join("docs/sidebar.yml"))
  end

  DOCS_BASE = Rails.root.join("docs/content").freeze
  SAFE_PATH = /\A[a-z0-9\-_\/]+\z/i.freeze

  def render_doc(path)
    # Validate path: only lowercase alphanumeric, hyphens, underscores, slashes
    raise ActiveRecord::RecordNotFound unless path.is_a?(String) && path.match?(SAFE_PATH)

    file = DOCS_BASE.join("#{path}.md").expand_path
    # Prevent path traversal: resolved path must be inside docs/content/
    raise ActiveRecord::RecordNotFound unless file.to_s.start_with?(DOCS_BASE.to_s + "/")
    raise ActiveRecord::RecordNotFound unless file.file?

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
    # Commonmarker v2 outputs: <pre lang="bash" style="..."><code><span>...</span></code></pre>
    html.gsub(%r{<pre lang="(\w+)"[^>]*><code>(.*?)</code></pre>}m) do
      lang = $1
      # Strip span tags and inline styles from commonmarker's built-in highlighting
      code = $2.gsub(/<span[^>]*>/, "").gsub("</span>", "")
      code = CGI.unescapeHTML(code)
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
    # Commonmarker v2 already generates anchors:
    #   <h2><a href="#id" aria-hidden="true" class="anchor" id="id"></a>Text</h2>
    # Just replace the invisible anchor with our styled one
    html.gsub(/<(h[23])><a href="#([^"]+)"[^>]*><\/a>(.*?)<\/\1>/i) do
      tag = $1
      id = $2
      text = $3
      %(<#{tag} id="#{id}"><a href="##{id}" class="docs-anchor">#</a>#{text}</#{tag}>)
    end
  end

  def extract_toc(html)
    # Match our output format: <h2 id="foo"><a ...>#</a>Text</h2>
    html.scan(/<(h[23]) id="([^"]+)"[^>]*>.*?<\/a>(.*?)<\/\1>/i).map do |tag, id, text|
      { level: tag == "h2" ? 2 : 3, id: id, text: text.strip }
    end
  end

  def find_prev_next(path)
    flat = load_sidebar.flat_map { |section| section["items"].map { |item| item["path"] } }
    idx = flat.index(path)
    return [ nil, nil ] unless idx

    prev_path = idx > 0 ? flat[idx - 1] : nil
    next_path = idx < flat.length - 1 ? flat[idx + 1] : nil

    prev_item = prev_path ? find_sidebar_item(prev_path) : nil
    next_item = next_path ? find_sidebar_item(next_path) : nil

    [ prev_item, next_item ]
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
