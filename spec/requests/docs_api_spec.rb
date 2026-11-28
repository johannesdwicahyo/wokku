require "rails_helper"

# API reference: one Redoc page per group, served from a sliced OpenAPI doc.
RSpec.describe "Docs API reference", type: :request do
  let(:html) { Nokogiri::HTML(response.body) }

  it "redirects /docs/api to the first group, keeping the language" do
    get "/docs/api"
    expect(response).to redirect_to("/docs/api/apps")
    get "/docs/api", params: { lang: "id" }
    expect(response).to redirect_to("/docs/api/apps?lang=id")
  end

  it "serves a group's slice as JSON with a 5-minute cache" do
    get "/docs/api/apps.json"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to include("max-age=300", "public")
    expect(response.headers["Set-Cookie"]).to be_blank
    body = JSON.parse(response.body)
    expect(body["paths"]).to include("/api/v1/apps")
    expect(body["paths"]).not_to include("/api/v1/apps/{id}/dokku")
  end

  it "uses the control-plane host (not the apps domain) for servers (ignoring a spoofed host) and stays publicly cacheable" do
    allow(Wokku.config).to receive(:canonical_domain).and_return("apps.example")
    allow(Wokku.config).to receive(:control_plane_host).and_return("wokku.example")
    get "/docs/api/apps.json", headers: { "X-Forwarded-Host" => "evil.example" }
    expect(JSON.parse(response.body)["servers"]).to eq([ { "url" => "https://wokku.example" } ])
    expect(response.headers["Cache-Control"]).to include("public")
    expect(Docs::ApiSlice.for("apps")["servers"]).not_to eq([ { "url" => "https://wokku.example" } ])
  end

  it "falls back to the request origin with a private response when no canonical domain is set" do
    allow(Wokku.config).to receive(:control_plane_host).and_return("localhost")
    get "/docs/api/apps.json"
    expect(JSON.parse(response.body)["servers"]).to eq([ { "url" => "http://www.example.com" } ])
    expect(response.headers["Cache-Control"]).to include("private")
    expect(response.headers["Cache-Control"]).not_to include("public")
  end

  it "404s the Email and storage group (page and JSON) unless object storage is on" do
    allow(Wokku.config).to receive(:object_storage?).and_return(false)
    get "/docs/api/email-storage"
    expect(response).to have_http_status(:not_found)
    get "/docs/api/email-storage.json"
    expect(response).to have_http_status(:not_found)
    get "/docs/api/apps"
    expect(html.at_css("nav[data-docs-api-groups]").text).not_to include("Email and storage")
    allow(Wokku.config).to receive(:object_storage?).and_return(true)
    get "/docs/api/email-storage"
    expect(response).to have_http_status(:ok)
  end

  it "404s an unknown or empty group" do
    get "/docs/api/nope.json"
    expect(response).to have_http_status(:not_found)
    allow(Docs::ApiSlice).to receive(:for).and_call_original
    allow(Docs::ApiSlice).to receive(:for).with("team-billing").and_return(nil)
    get "/docs/api/team-billing"
    expect(response).to have_http_status(:not_found)
  end

  it "404s /docs/api when there are no groups" do
    allow(Docs::ApiSlice).to receive(:groups).and_return([])
    get "/docs/api"
    expect(response).to have_http_status(:not_found)
  end

  it "leaves the API guides at /docs/api/<page>" do
    get "/docs/api/endpoints"
    expect(response).to have_http_status(:ok)
    expect(html.at_css("[data-controller='redoc']")).to be_nil
  end

  it "renders the page: top bar on API, group nav, Redoc mount, pinned script, fallback" do
    get "/docs/api/addons"
    expect(response).to have_http_status(:ok)
    expect(html.at_css("header[data-docs-top-bar] nav a[aria-current='page']").text.strip).to eq("API reference")
    nav = html.at_css("nav[data-docs-api-groups]")
    expect(nav.css("a").map { |a| a.text.strip }).to include("Apps and deploys", "Add-ons", "Domains", "Auth and tokens")
    expect(nav.at_css("a[aria-current='page']").text.strip).to eq("Add-ons")
    mount = html.at_css("[data-controller='redoc']")
    expect(mount["data-redoc-url-value"]).to eq("/docs/api/addons.json")
    script = html.at_css("script[src*='redoc']")
    expect(script["src"]).to eq("https://cdn.jsdelivr.net/npm/redoc@2.1.5/bundles/redoc.standalone.js")
    expect(script["integrity"]).to eq("sha384-0GrsyTQc9Oqd8h+b2dbc4XdR2T/DYpy0tLNNstyx+LBMUyiBbcWPbEs9aRmUcaxD")
    expect(script["crossorigin"]).to eq("anonymous")
    expect(script).to have_attributes(attributes: include("data-redoc-script"))
    fallback = html.at_css("noscript").inner_html
    expect(fallback).to include("This reference needs JavaScript", "/api/v1/openapi.yaml")
  end

  it "renders the group intro as markdown" do
    allow(Wokku.config).to receive(:docs_api_group_intros).and_return({ "domains" => "Point **a name** at an app." })
    get "/docs/api/domains"
    expect(html.at_css("[data-docs-api-intro] strong").text).to eq("a name")
  end

  it "loads the Redoc script only on API pages" do
    get "/docs/getting-started/sign-up"
    expect(response.body).not_to include("redoc.standalone.js")
  end

  it "shows the chrome in id on ?locale=id and ?lang=id" do
    [ { locale: "id" }, { lang: "id" } ].each do |params|
      get "/docs/api/apps", params: params
      expect(html.at_css("html")["lang"]).to eq("id")
      expect(html.at_css("nav[data-docs-api-groups] a[aria-current='page']").text.strip).to eq("Aplikasi dan deploy")
      expect(html.at_css("noscript").inner_html).to include("Referensi ini butuh JavaScript")
    end
  end

  it "links the API reference from the guides sidebar" do
    get "/docs/api/endpoints"
    expect(html.at_css(".docs-grid__side a[href='/docs/api']")).to be_present
  end
end
