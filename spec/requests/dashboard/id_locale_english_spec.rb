# frozen_string_literal: true

require "rails_helper"

# Phase 1 sweep ledger: English UI strings that leaked onto Indonesian pages.
# Dev words the copy deck keeps (app, deploy, add-on, dashboard, template,
# live, push, build, rollback) are NOT in the list.
RSpec.describe "Indonesian pages carry no leaked English UI strings", type: :request do
  include Devise::Test::IntegrationHelpers

  LEAKED = [
    "Settings", "Servers", "Users", "Overview", "Back to dashboard", "Cloud credentials",
    "Sign out", "Search or run a command", "Language", "Account", "Workspace",
    "No apps yet", "Create app", "Save changes", "Delete", "Cancel", "Loading",
    "Export CSV", "Apply", "Since", "Until", "Any", "Recent activity", "Recent logs",
    "No recent activity", "Member since", "Preferences", "Two-factor auth", "Enable 2FA",
    "Manage your servers", "Capacity", "Quick links", "View all", "Read-only", "Full access",
    "Never expires", "No tokens yet", "No keys yet", "Add SSH Key", "Active Apps",
    "Deploy command", "Public Git repository", "curated picks", "Create App", "Resize anytime", "API endpoint", "Auth header", "Documentation"
  ].freeze

  def visible_text(html)
    doc = Nokogiri::HTML(html)
    doc.css("script, style, noscript, template, [hidden]").remove
    doc.text.gsub(/\s+/, " ")
  end

  def leaks_at(path)
    get path, params: { locale: "id" }
    expect(response).to have_http_status(:success)
    text = visible_text(response.body)
    LEAKED.select { |w| text.match?(/(?<![\w-])#{Regexp.escape(w)}(?![\w-])/) }
  end

  {
    "apps index" => "/dashboard/apps",
    "add-ons index" => "/dashboard/addons",
    "templates" => "/dashboard/templates",
    "activity" => "/dashboard/activities",
    "profile/settings" => "/dashboard/profile"
  }.each do |name, path|
    it "#{name} (#{path})" do
      sign_in users(:one)
      expect(leaks_at(path)).to be_empty
    end
  end

  it "an app overview" do
    sign_in users(:two)
    expect(leaks_at("/dashboard/apps/#{app_records(:two).id}")).to be_empty
  end

  it "admin servers" do
    sign_in users(:admin)
    expect(leaks_at("/admin/servers")).to be_empty
  end
end
