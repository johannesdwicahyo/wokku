# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard resources app_resource_sections", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:app_record) { app_records(:two) }
  let(:path) { "/dashboard/apps/#{app_record.id}/resources" }

  before do
    sign_in users(:two)
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming).and_return("")
  end
  after { Wokku.config.app_resource_sections = nil }

  it "renders nothing extra by default" do
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("SectionMarker")
  end

  it "renders each configured partial with its locals" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/spec_sections")
      File.write("#{dir}/spec_sections/_card.html.erb", "<p>SectionMarker <%= name %></p>")
      Dashboard::ResourcesController.prepend_view_path(dir)
      Wokku.config.app_resource_sections = ->(_view, app) {
        [ { partial: "spec_sections/card", locals: { name: app.name } } ]
      }
      get path
      expect(response.body).to include("SectionMarker #{app_record.name}")
    ensure
      Dashboard::ResourcesController.view_paths = Dashboard::ResourcesController.view_paths.to_a.reject { |p| p.to_s == dir }
    end
  end
end
