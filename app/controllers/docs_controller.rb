class DocsController < ApplicationController
  layout "docs"

  SUPPORTED_LOCALES = %w[en id].freeze
  DEFAULT_LOCALE    = "en".freeze

  # Pages merged or retired in the 2026-11 docs refresh → where their
  # content lives now. Keeps old links and search results working.
  MOVED = {
    "templates/deploy" => "templates/browse",
    "apps/create" => "apps/deploy",
    "apps/logs" => "monitoring/logs",
    "guides/postgres-redis" => "databases/create-link",
    "databases/dedicated-upgrade" => "databases/create-link",
    "domains-ssl/ssl" => "domains-ssl/custom-domains",
    "scaling/tiers" => "scaling/resources",
    "billing/plans" => "billing/pricing",
    "billing/plan-bundles" => "billing/pricing",
    "billing/usage" => "billing/invoices",
    "observability/retention" => "monitoring/logs",
    "workspaces/switching" => "workspaces/personal-vs-org",
    "teams/permissions" => "teams/members",
    "mobile/notifications" => "mobile/download",
    "getting-started/connect-server" => "oss/connect-server",
    "cli" => "cli/install" # the docs top bar's CLI tab
  }.freeze

  # Pages hidden (404, not in sidebar/search) until their feature is on.
  # Billing pages describe wokku.cloud's plans/invoices: cloud-only.
  GATED = {
    "databases/object-storage" => -> { Wokku.config.object_storage? },
    "billing/pricing"          => -> { Wokku.cloud? },
    "billing/invoices"         => -> { Wokku.cloud? },
    "beta"                     => -> { Wokku.cloud? }
  }.freeze

  def show
    raise ActiveRecord::RecordNotFound if gated?(params[:path])
    if (target = MOVED[params[:path]])
      return redirect_to docs_page_path(target, lang: params[:lang].presence), status: :moved_permanently
    end

    @docs_locale = resolve_locale
    I18n.locale = @docs_locale # chrome labels follow the page language (?lang=)
    @path = params[:path] || "getting-started/first-deploy"
    @sidebar = load_sidebar(@docs_locale)

    rendered = render_doc(@path, @docs_locale)
    @content      = unlink_gated(rendered[:html])
    @frontmatter  = rendered[:frontmatter]
    @doc_title    = @frontmatter["title"] || extract_h1(@content) || @path.split("/").last.titleize
    @doc_summary  = @frontmatter["summary"]
    @doc_eyebrow  = @frontmatter["eyebrow"] || default_eyebrow(@path)
    @doc_badges   = Array(@frontmatter["badges"])
    @doc_edited   = @frontmatter["last_updated"]
    @doc_edit_url = @frontmatter["edit_url"] || default_edit_url(@path, @docs_locale)

    @toc = extract_toc(@content)
    @prev_item, @next_item = find_prev_next(@path, @docs_locale)
    @breadcrumb = build_breadcrumb(@path)
  end

  def search_index
    locale = resolve_locale
    base = DOCS_BASE.join(locale)
    base = DOCS_BASE.join(DEFAULT_LOCALE) unless base.directory?

    entries = []
    Dir.glob(base.join("**/*.md")).each do |file|
      path = file.sub(base.to_s + "/", "").sub(".md", "")
      next if gated?(path)
      raw = File.read(file)
      frontmatter, content = split_frontmatter(raw)
      title = frontmatter["title"].presence ||
              content.match(/^# (.+)/)&.captures&.first ||
              path.split("/").last.titleize
      headings = content.scan(/^## (.+)/).flatten
      excerpt_source = frontmatter["summary"].presence || content
      body = excerpt_source.gsub(/^#+ /, "").gsub(/```.*?```/m, "").gsub(/:::.*?:::/m, "").gsub(/::\S+/, "").strip[0..300]
      entries << { title: title, path: path, headings: headings, excerpt: body }
    end
    render json: entries
  end

  private

  def gated?(path) = (check = GATED[path]) && !check.call

  # In-page links to a hidden page would 404; keep the text, drop the link.
  def unlink_gated(html)
    html.gsub(%r{<a href="/docs/([a-z0-9\-_/]+)[^"]*"[^>]*>(.*?)</a>}m) { gated?(Regexp.last_match(1)) ? Regexp.last_match(2) : Regexp.last_match(0) }
  end

  # Locale source order: explicit ?lang= param → I18n.locale → default.
  def resolve_locale
    candidate = params[:lang].presence || I18n.locale.to_s
    SUPPORTED_LOCALES.include?(candidate) ? candidate : DEFAULT_LOCALE
  end

  def load_sidebar(locale)
    @_sidebar ||= {}
    @_sidebar[locale] ||= begin
      file = Wokku::Engine.root.join("docs/sidebar.#{locale}.yml")
      file = Wokku::Engine.root.join("docs/sidebar.#{DEFAULT_LOCALE}.yml") unless file.file?
      YAML.load_file(file)
        .each { |section| section["items"]&.reject! { |item| gated?(item["path"]) } }
        .reject { |section| section.key?("items") && section["items"].empty? }
    end
  end

  DOCS_BASE = Wokku::Engine.root.join("docs/content").freeze
  SAFE_PATH = /\A[a-z0-9\-_\/]+\z/i.freeze

  # Returns { html:, frontmatter: }. Frontmatter is the parsed YAML
  # block at the top of the markdown file (or {} if absent).
  def render_doc(path, locale)
    raise ActiveRecord::RecordNotFound unless path.is_a?(String) && path.match?(SAFE_PATH)

    file = doc_file_for(path, locale)
    raise ActiveRecord::RecordNotFound unless file&.file?
    @doc_locale_actual = file.to_s.include?("/#{locale}/") ? locale : DEFAULT_LOCALE

    raw = file.read
    frontmatter, body = split_frontmatter(raw)
    body = preprocess_callouts(body)
    body = preprocess_tabs(body)
    html = render_markdown(body)
    html = add_heading_anchors(html)
    { html: html, frontmatter: frontmatter }
  end

  def doc_file_for(path, locale)
    [ locale, DEFAULT_LOCALE ].uniq.each do |loc|
      candidate = DOCS_BASE.join(loc, "#{path}.md").expand_path
      next unless candidate.to_s.start_with?(DOCS_BASE.to_s + "/")
      return candidate if candidate.file?
    end
    nil
  end

  # Parses an optional YAML frontmatter block delimited by --- at the
  # very top of the file. Returns [frontmatter_hash, body_string].
  def split_frontmatter(raw)
    if raw.start_with?("---\n")
      end_idx = raw.index("\n---\n", 4)
      if end_idx
        fm_yaml = raw[4...end_idx]
        body    = raw[(end_idx + 5)..]
        fm = YAML.safe_load(fm_yaml, permitted_classes: [ Date, Time ]) || {}
        return [ fm, body.to_s ]
      end
    end
    [ {}, raw ]
  end

  def render_markdown(text)
    html = Commonmarker.to_html(text, options: {
      parse: { smart: true },
      render: { unsafe: true }
    })
    highlight_code_blocks(html)
  end

  # Every fenced block → `.doc-code` with a Copy button (copy-code
  # controller; `hidden` until JS runs). `doc-pre` marks a wrapped block so
  # the outer pass doesn't re-wrap blocks already rendered inside callouts/tabs.
  def highlight_code_blocks(html)
    formatter = Rouge::Formatters::HTML.new
    html.gsub(%r{<pre(?![^>]*doc-pre)(?: lang="([\w+-]+)")?[^>]*><code>(.*?)</code></pre>}m) do
      lang = $1
      code = CGI.unescapeHTML($2.gsub(/<span[^>]*>/, "").gsub("</span>", ""))
      lexer = (lang && Rouge::Lexer.find(lang)) || Rouge::Lexers::PlainText.new
      code_block_html(lang, formatter.format(lexer.lex(code)))
    end
  end

  def code_block_html(lang, highlighted)
    %(<div class="doc-code docs-code-block" data-controller="copy-code" data-copy-code-copied-value="#{ERB::Util.h(I18n.t("docs.copy.copied"))}">) +
      %(<div class="doc-code__bar"><span class="docs-code-lang">#{ERB::Util.h(lang)}</span>) +
      %(<button type="button" class="doc-copy" hidden data-copy-code-target="button" data-action="copy-code#copy">#{ERB::Util.h(I18n.t("docs.copy.copy"))}</button>) +
      %(<span class="sr-only" aria-live="polite" data-copy-code-target="status"></span></div>) +
      %(<pre class="doc-pre"><code>#{highlighted}</code></pre></div>)
  end

  # Pre-processor: `:::callout note\n...\n:::` → CalloutComponent.
  # Tones: note | warn | success | danger; the guides write `tip` and
  # `warning`, which used to fall through to a green "Note".
  CALLOUT_ALIASES = { tip: :success, warning: :warn }.freeze

  def preprocess_callouts(content)
    content.gsub(/:::callout(?:\s+(\w+))?\n(.*?):::/m) do
      tone = ($1 || "note").to_sym
      tone = CALLOUT_ALIASES.fetch(tone, tone)
      tone = :note unless %i[note warn success danger].include?(tone)
      body = render_markdown($2.strip)
      # with_content, not a block: controller render drops a block, which
      # left every callout an empty box.
      ApplicationController.render(
        Molecules::CalloutComponent.new(tone: tone).with_content(body.html_safe),
        layout: false
      )
    rescue StandardError
      # Fallback: emit a plain div so a malformed block doesn't blank
      # the page. Keeps the docs survivable during authoring.
      %(<div class="docs-callout docs-callout-#{tone}">#{$2}</div>)
    end
  end

  # Pre-processor: `:::tabs\n::<id>\n...\n::<id>\n...\n:::` → CodeTabsComponent.
  def preprocess_tabs(content)
    content.gsub(/:::tabs\n(.*?):::/m) do
      tabs_content = $1
      channels = tabs_content.scan(/::(\S+)\n(.*?)(?=::\S|\z)/m)
      tabs = channels.map do |key, body|
        { id: key, label: tab_label(key), html: render_markdown(body.strip) }
      end
      tabs_to_html(tabs)
    end
  end

  def tabs_to_html(tabs)
    return "" if tabs.empty?
    first_id = tabs.first[:id]
    buttons = tabs.map do |t|
      %(<button type="button" class="tab-btn #{t[:id] == first_id ? 'is-active' : ''}" data-action="click->code-tabs#select" data-id="#{t[:id]}" data-code-tabs-target="tab">#{t[:label]}</button>)
    end.join("\n")
    panels = tabs.map do |t|
      hidden = t[:id] == first_id ? "" : "hidden"
      %(<div class="px-5 py-5" data-code-tabs-target="panel" data-id="#{t[:id]}" #{hidden}>#{t[:html]}</div>)
    end.join("\n")
    <<~HTML
      <div class="mt-4 border border-line rounded-md overflow-hidden bg-paper shadow-brutal-sm" data-controller="code-tabs" data-code-tabs-default-value="#{first_id}">
        <div class="flex border-b border-line bg-bg-deep" style="overflow-x: auto;">
          #{buttons}
        </div>
        #{panels}
      </div>
    HTML
  end

  def tab_label(key)
    {
      "web-ui" => "// web_ui",
      "cli"    => "// cli",
      "api"    => "// api",
      "mcp"    => "// claude_code",
      "mobile" => "// mobile",
      "github" => "// github"
    }.fetch(key, "// #{key}")
  end

  def add_heading_anchors(html)
    # docs.css renders the `# ` prefix on h2 via ::before, so we only
    # need the anchor id for deep links here — no inline `#` link.
    # Without this guard the heading reads "# # Foo".
    html.gsub(/<(h[23])><a href="#([^"]+)"[^>]*><\/a>(.*?)<\/\1>/i) do
      tag = $1
      id = $2
      text = $3
      %(<#{tag} id="#{id}">#{text}</#{tag}>)
    end
  end

  def extract_toc(html)
    # After PR-3's add_heading_anchors simplification the inline <a>
    # anchor inside the heading is gone; match the heading id directly.
    html.scan(/<(h[23]) id="([^"]+)"[^>]*>(.*?)<\/\1>/im).map do |tag, id, text|
      # Plain text: commonmarker 2.9 nests an <a class="anchor"> in each
      # heading, which would otherwise show up as literal markup.
      { level: tag == "h2" ? 2 : 3, id: id, text: ActionController::Base.helpers.strip_tags(text).strip }
    end
  end

  def extract_h1(html)
    # Strip Commonmarker's auto-anchor (empty `<a aria-hidden>`) + any
    # other inline tags so the title we feed to DocHeader is plain
    # text. Without this, ERB HTML-escapes the inner `<a>` and we'd
    # render the literal anchor attributes inside the H1.
    #
    # Then decode HTML entities (`&amp;` → `&`, `&lt;` → `<`, etc.)
    # so titles like "Create & Link" don't render as "Create &amp; Link"
    # after ERB re-escapes the already-entity-encoded source.
    match = html.match(/<h1[^>]*>(.*?)<\/h1>/im)
    return nil unless match
    plain = match[1].gsub(/<[^>]+>/, "").strip
    CGI.unescapeHTML(plain)
  end

  def find_prev_next(path, locale)
    sidebar = load_sidebar(locale)
    flat = sidebar.flat_map do |section|
      section["items"].map { |item| { "title" => item["title"], "path" => item["path"] } }
    end
    idx = flat.index { |item| item["path"] == path }
    return [ nil, nil ] unless idx

    prev_item = idx > 0 ? flat[idx - 1] : nil
    next_item = idx < flat.length - 1 ? flat[idx + 1] : nil
    [ prev_item, next_item ]
  end

  def build_breadcrumb(path)
    crumbs = [ [ "~/docs", "/docs" ] ]
    parts = path.split("/")
    if parts.length > 1
      crumbs << [ parts[0..-2].join("/").tr("-", " "), nil ]
    end
    crumbs << [ parts.last.tr("-", " "), nil ]
    crumbs
  end

  def default_eyebrow(path)
    parts = path.split("/")
    parts.length > 1 ? parts.first.tr("-", "_") : nil
  end

  def default_edit_url(path, locale)
    "https://github.com/johannesdwicahyo/wokku-cloud/edit/main/docs/content/#{locale}/#{path}.md"
  end
end
