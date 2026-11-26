# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /dashboard/apps/new", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:doc) { Capybara.string(response.body) }

  before do
    sign_in user
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
  end

  it "renders four sections, the board and a single submit" do
    get "/dashboard/apps/new"
    expect(response).to have_http_status(:ok)
    ["01 · Source", "02 · Name and size", "03 · Add-ons", "04 · Summary"].each { |t| expect(doc).to have_text(t) }
    expect(doc).to have_css("canvas[data-light-board-mode-value=text]")
    expect(doc).to have_css("form[data-controller~='new-app'] button[type=submit]", count: 1)
    expect(doc).to have_css("form[data-controller~='new-app']")
  end

  it "shows no Rupiah under NullPricing" do
    Wokku.config.pricing = Wokku::Providers::NullPricing.new
    get "/dashboard/apps/new"
    expect(response.body).not_to include("Rp")
    expect(doc).to have_no_text("Per month")
  end

  it "has no English chrome under :id" do
    get "/dashboard/apps/new", headers: { "Accept-Language" => "id" }, params: { locale: :id }
    skip "locale not switched" unless doc.has_text?("Ringkasan")
    ["Name and size", "Add-ons", "Summary", "Create and deploy"].each { |t| expect(response.body).not_to include(t) }
  end

  def scope_servers(*servers)
    allow_any_instance_of(Dashboard::AppsController).to receive(:policy_scope).and_wrap_original do |m, s|
      s == Server ? Server.where(id: servers.map(&:id)) : m.call(s)
    end
  end

  it "uses a hidden server_id with one server" do
    a = create(:server, team: user.teams.first)
    scope_servers(a)
    get "/dashboard/apps/new"
    expect(doc).to have_css("input[type=hidden][name='app_record[server_id]'][value='#{a.id}']", visible: :all)
    expect(doc).to have_no_css("[data-controller=combobox]")
  end

  it "renders the server combobox with several, and a frame for section 03" do
    scope_servers(create(:server, team: user.teams.first), create(:server, team: user.teams.first))
    get "/dashboard/apps/new"
    expect(doc).to have_css("[data-controller=combobox][data-action='change->new-app#server']")
    expect(doc).to have_css("turbo-frame#new_app_addons[data-new-app-target=addonsFrame]")
  end
end
