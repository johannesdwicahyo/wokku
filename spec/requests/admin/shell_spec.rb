# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin shell", type: :request do
  include Devise::Test::IntegrationHelpers
  include Capybara::RSpecMatchers

  it "renders the rail with the admin group, the Admin crumb and the palette" do
    sign_in users(:admin)
    get "/admin/servers"
    doc = Capybara.string(response.body)
    expect(doc.find("aside nav[aria-label='Workspace']")).to have_link("Servers", href: "/admin/servers")
    expect(doc.find("aside nav[aria-label='Account']")).to have_link("Back to dashboard")
    expect(doc).to have_css("header", text: "Admin")
    expect(doc).to have_css("[role='dialog'][aria-modal='true']", visible: :all)
    expect(response.body).not_to include("mobile-nav")
  end
end
