require "rails_helper"

# Control-room reading layout for /docs guides (Phase 10, Task 1).
RSpec.describe "Docs reading layout", type: :request do
  include Devise::Test::IntegrationHelpers
  def html = Nokogiri::HTML(response.body)

  it "renders the docs top bar instead of the cloud site nav" do
    get "/docs/getting-started/sign-up"
    bar = html.at_css("header[data-docs-top-bar]")
    expect(bar).to be_present
    tabs = bar.css("nav a").map { |a| [ a.text.strip, a["href"] ] }
    expect(tabs).to include([ "Guides", "/docs" ], [ "API reference", "/docs/api" ], [ "CLI", "/docs/cli" ])
    expect(bar.at_css("nav a[aria-current='page']").text.strip).to eq("Guides")
    expect(bar.at_css("button[data-action~='docs-search#open']")).to be_present
    expect(bar.css("form[action^='/locale'] button").map(&:text).map(&:strip)).to eq(%w[EN ID])
    expect(bar.at_css("a[href='/users/sign_in']")).to be_present
    layout = File.read(Wokku::Engine.root.join("app/views/layouts/docs.html.erb"))
    expect(layout).not_to include("SiteNavComponent")
  end

  it "shows the Changelog tab only when a changelog route exists" do
    get "/docs/getting-started/sign-up"
    has_route = Rails.application.routes.url_helpers.respond_to?(:changelog_path)
    expect(html.css("header[data-docs-top-bar] nav a").map { |a| a.text.strip }.include?("Changelog")).to eq(has_route)
  end

  it "shows Dashboard to a signed-in user" do
    sign_in create(:user)
    get "/docs/getting-started/sign-up"
    expect(html.at_css("header[data-docs-top-bar] a[href='/dashboard']")).to be_present
  end

  it "marks the CLI tab active on CLI pages, and /docs/cli lands on the CLI guide" do
    get "/docs/cli/commands"
    expect(html.at_css("header[data-docs-top-bar] nav a[aria-current='page']").text.strip).to eq("CLI")
    get "/docs/cli"
    expect(response).to redirect_to("/docs/cli/install")
  end

  it "wraps every code block with a copy button hidden until JS runs" do
    get "/docs/getting-started/first-deploy"
    blocks = html.css("div.doc-code[data-controller='copy-code']")
    expect(blocks).not_to be_empty
    blocks.each do |b|
      btn = b.at_css("button[data-copy-code-target='button']")
      expect(btn).to be_present
      expect(btn["hidden"]).not_to be_nil
      expect(btn.text.strip).to eq("Copy")
      expect(b.at_css("[aria-live='polite']")).to be_present
      expect(b.at_css("pre code")).to be_present
    end
    expect(html.css("pre").count).to eq(html.css("div.doc-code pre").count)
    expect(html.css("div.doc-code div.doc-code")).to be_empty
  end

  it "gives the TOC links scrollspy targets" do
    get "/docs/getting-started/first-deploy"
    toc = html.at_css("[data-controller~='docs-scrollspy']")
    expect(toc).to be_present
    links = toc.css("a[data-docs-scrollspy-target='link']")
    expect(links).not_to be_empty
    expect(links.first["aria-current"]).to eq("true")
  end

  # The guides write `warning` and `tip`; both used to fall through to "Note".
  it "renders `warning` callouts amber and `tip` callouts as tips" do
    get "/docs/databases/backups"
    expect(html.at_css(".doc-callout-warn[role='note']")["style"]).to include("--color-warn")
    expect(html.at_css(".doc-callout-success")).to be_present
  end

  it "uses Indonesian chrome labels on ?locale=id" do
    get "/docs/getting-started/sign-up", params: { locale: "id" }
    bar = html.at_css("header[data-docs-top-bar]")
    expect(bar.css("nav a").map { |a| a.text.strip }).to include("Panduan", "Referensi API")
    expect(bar.text).to include("Cari docs")
    expect(bar.text).to include("Masuk")
    get "/docs/getting-started/first-deploy", params: { locale: "id" }
    expect(html.at_css("button[data-copy-code-target='button']").text.strip).to eq("Salin")
    expect(html.at_css("[data-copy-code-copied-value]")["data-copy-code-copied-value"]).to eq("Tersalin")
  end

  it "labels callouts in the page language" do
    get "/docs/databases/backups", params: { locale: "id" }
    expect(html.at_css(".doc-callout-warn .doc-callout__label").text.strip).to eq("Hati-hati")
    get "/docs/databases/backups", params: { locale: "en" }
    expect(html.at_css(".doc-callout-warn .doc-callout__label").text.strip).to eq("Careful")
  end

  it "gives phones a scrollable row of section links" do
    get "/docs/getting-started/sign-up"
    row = html.at_css("header[data-docs-top-bar] nav.min-\\[900px\\]\\:hidden[aria-label]")
    expect(row).to be_present
    expect(row["class"]).to include("overflow-x-auto")
    expect(row.css("a").map { |a| a["href"] }).to include("/docs", "/docs/api", "/docs/cli")
    expect(row.at_css("a[aria-current='page']").text.strip).to eq("Guides")
  end

  it "searches the page's language" do
    js = File.read(Wokku::Engine.root.join("app/javascript/controllers/docs_search_controller.js"))
    expect(js).to include("search-index.json?lang=${encodeURIComponent(document.documentElement.lang")
    get "/docs/search-index.json", params: { lang: "id" }
    expect(response).to have_http_status(:ok)
  end

  it "uses Indonesian chrome labels on ?lang=id too" do
    get "/docs/getting-started/sign-up", params: { lang: "id" }
    expect(html.at_css("header[data-docs-top-bar] nav a[aria-current='page']").text.strip).to eq("Panduan")
  end
end
