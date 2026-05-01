require "yaml"

# Lightweight reader for the markdown blog posts in `db/blog/`. We use a
# PORO instead of an ActiveRecord model because the content lives on
# disk (deploy-bundled), edited via PR, not via the dashboard.
#
# Each .md file looks like:
#   ---
#   title: "..."
#   date: 2026-03-15
#   author: Johannes Dwicahyo
#   description: "..."
#   tags: ["architecture", "open-source"]
#   ---
#
#   markdown body...
class BlogPost
  CONTENT_DIR = Rails.root.join("db", "blog")
  FRONT_MATTER_RE = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

  attr_reader :slug, :title, :date, :author, :description, :tags, :body_markdown

  def self.all
    Dir.glob(CONTENT_DIR.join("*.md")).map { |f| from_file(f) }.sort_by { |p| p.date }.reverse
  end

  def self.find(slug)
    path = CONTENT_DIR.join("#{slug}.md")
    return nil unless File.exist?(path) && slug.match?(/\A[a-z0-9\-]+\z/)
    from_file(path)
  end

  def self.from_file(path)
    raw = File.read(path)
    match = raw.match(FRONT_MATTER_RE)
    raise "Blog post #{path} missing YAML front-matter" unless match
    meta = YAML.safe_load(match[1], permitted_classes: [ Date, Time ])
    body = match[2]
    new(slug: File.basename(path, ".md"), meta: meta, body_markdown: body)
  end

  def initialize(slug:, meta:, body_markdown:)
    @slug = slug
    @title = meta["title"].to_s
    @date = meta["date"].is_a?(Date) ? meta["date"] : Date.parse(meta["date"].to_s)
    @author = meta["author"].to_s
    @description = meta["description"].to_s
    @tags = Array(meta["tags"])
    @body_markdown = body_markdown
  end

  def body_html
    Commonmarker.to_html(@body_markdown,
      options: { parse: { smart: true }, render: { unsafe: true } }
    ).html_safe
  end

  def to_param
    slug
  end
end
