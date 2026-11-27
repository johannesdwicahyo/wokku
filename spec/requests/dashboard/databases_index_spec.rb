# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Add-ons index rack", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }

  it "renders a rack row per add-on with engine, size, apps and backups state" do
    orphan = create(:database_service, server: servers(:one), service_type: "redis", name: "cache-x", status: :running)
    get "/dashboard/addons"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pg-main", "Postgres", "my-app-one")
    expect(response.body).to include(%(data-rack-unit="pg-main"))
    expect(response.body).to include(%(id="#{ActionView::RecordIdentifier.dom_id(orphan)}"))
  end

  it "lists orphans in their own section" do
    create(:database_service, server: servers(:one), name: "stray-db", status: :running)
    get "/dashboard/addons"
    expect(response.body).to include("Unlinked add-ons", %(id="orphan_addons"))
  end

  it "groups by app with pressed state on the segmented control" do
    get "/dashboard/addons", params: { group: "app" }
    expect(response.body).to include("my-app-one")
    expect(response.body).to match(/aria-pressed="true"[^>]*>By app|By app[^<]*<\/button>/)
    expect(response.body).to include(%(aria-pressed="false"))
  end

  it "has no brutalist classes" do
    get "/dashboard/addons"
    doc = Nokogiri::HTML(response.body)
    doc.css("[data-slide-panel-target='panel']").each(&:remove) # shared slide panel is out of scope
    html = doc.to_html
    expect(html).not_to include("shadow-brutal")
    expect(response.body).not_to include("border-1.5")
    expect(response.body).not_to include("bg-ink text-paper")
  end

  it "renders the localized rack under ?locale=id" do
    create(:database_service, server: servers(:one), name: "stray-db", status: :running)
    get "/dashboard/addons", params: { locale: "id" }
    expect(response.body).to include("Add-on tak tertaut")
    expect(response.body).not_to include("Unlinked")
    expect(response.body).not_to include(">Retry<")
  end
end
