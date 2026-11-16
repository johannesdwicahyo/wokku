require "rails_helper"

RSpec.describe "DocsController", type: :request do
  it "GET /docs renders successfully" do
    get "/docs"
    expect(response).to have_http_status(:success)
  end

  it "renders a docs page" do
    get "/docs/getting-started/sign-up"
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/Sign Up/)
  end

  it "returns 404 for a nonexistent docs path" do
    get "/docs/nonexistent"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the sidebar navigation" do
    get "/docs/getting-started/sign-up"
    expect(response.body).to include("/docs/getting-started/sign-up")
  end

  it "renders tabs with channel buttons" do
    get "/docs/getting-started/sign-up"
    expect(response).to have_http_status(:success)
    # PR-2: `:::tabs` blocks now emit the brutalist CodeTabs DOM
    # (data-controller="code-tabs"). Old `docs-tabs` markup retired.
    expect(response.body).to include('data-controller="code-tabs"')
    expect(response.body).to include("tab-btn")
    expect(response.body).to include('data-code-tabs-target="panel"')
  end

  it "exposes a JSON search index" do
    get "/docs/search-index.json"
    expect(response).to have_http_status(:success)
    json = JSON.parse(response.body)
    expect(json).to be_an(Array)
    expect(json.any? { |entry| entry["path"] == "getting-started/sign-up" }).to be true
    expect(json.first.key?("title")).to be true
    expect(json.first.key?("headings")).to be true
    expect(json.first.key?("excerpt")).to be true
  end

  it "renders syntax-highlighted code blocks" do
    get "/docs/getting-started/first-deploy"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("docs-code-block")
  end

  it "renders prev/next links" do
    get "/docs/getting-started/sign-up"
    expect(response.body).to include("/docs/getting-started/first-deploy")
    expect(response.body).to include("/docs/apps/ssh-keys")
  end

  it "301-redirects a merged page to its new home, keeping the language" do
    get "/docs/billing/plans", params: { lang: "id" }
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/docs/billing/pricing?lang=id")
  end

  it "renders every sidebar page in both languages" do
    allow(Wokku.config).to receive(:object_storage?).and_return(true) # feature-gated pages
    allow(Wokku).to receive(:cloud?).and_return(true) # cloud-only billing pages
    %w[en id].each do |locale|
      YAML.load_file(Wokku::Engine.root.join("docs/sidebar.#{locale}.yml")).flat_map { |s| s["items"] }.each do |item|
        get "/docs/#{item["path"]}", params: { lang: locale }
        expect(response).to have_http_status(:success), "#{locale} sidebar → #{item["path"]} gave #{response.status}"
      end
    end
  end

  it "renders the table of contents controller" do
    get "/docs/getting-started/sign-up"
    expect(response.body).to include("data-controller=\"docs-toc\"")
  end

  it "loads every sidebar page" do
    allow(Wokku.config).to receive(:object_storage?).and_return(true) # feature-gated pages
    allow(Wokku).to receive(:cloud?).and_return(true) # cloud-only billing pages
    sidebar = YAML.load_file(Wokku::Engine.root.join("docs/sidebar.en.yml"))
    sidebar.each do |section|
      section["items"].each do |item|
        get "/docs/#{item['path']}"
        expect(response).to have_http_status(:success), "Failed to load /docs/#{item['path']}"
      end
    end
  end

  describe "bilingual support" do
    it "defaults to English when no lang param" do
      get "/docs/getting-started/sign-up"
      expect(response).to have_http_status(:success)
    end

    it "accepts ?lang=id and falls back to English content when ID translation missing" do
      get "/docs/getting-started/sign-up?lang=id"
      expect(response).to have_http_status(:success)
      # English content rendered because no ID translation exists yet.
      expect(response.body).to match(/Sign Up/)
    end

    it "rejects unsupported lang values by silently falling back to English" do
      get "/docs/getting-started/sign-up?lang=fr"
      expect(response).to have_http_status(:success)
    end

    it "renders the Indonesian sidebar section titles when ?lang=id" do
      get "/docs/getting-started/sign-up?lang=id"
      # `Getting Started` → `Mulai` in the ID sidebar.
      expect(response.body).to include("Mulai")
    end

    it "renders the English sidebar section titles when ?lang=en" do
      get "/docs/getting-started/sign-up?lang=en"
      expect(response.body).to include("Getting Started")
    end


    it "search-index defaults to English content" do
      get "/docs/search-index.json"
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.any? { |e| e["path"] == "getting-started/sign-up" }).to be(true)
    end
  end

  # commonmarker 2.9 puts an <a class="anchor"> inside every heading; the
  # "on this page" list copied the heading HTML, so it showed the raw
  # anchor markup as text (seen on self-host, 2026-11-16 visual audit).
  it "lists plain heading text in the table of contents" do
    get "/docs/getting-started/first-deploy", params: { lang: "en" }
    expect(response.body).not_to include("&lt;a href=&quot;#")
    expect(response.body).not_to include("Link to heading &#39;")
  end
end
