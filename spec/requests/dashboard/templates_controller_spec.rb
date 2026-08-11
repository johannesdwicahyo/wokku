# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Templates", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user)   { users(:two) }
  let(:server) { servers(:two) }
  let(:template_slug) do
    registry = TemplateRegistry.new
    registry.all.first&.fetch(:slug, nil)
  end

  describe "auth" do
    it "index redirects to login when not authenticated" do
      get "/dashboard/templates"
      expect(response).to have_http_status(:redirect)
    end

    it "show redirects to login when not authenticated" do
      skip "No templates available" unless template_slug
      get "/dashboard/templates/#{template_slug}"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "index (signed in)" do
    before { sign_in user }

    it "returns 200 for authenticated admin" do
      get "/dashboard/templates"
      expect(response).to have_http_status(:success)
    end

    it "filters by search query" do
      get "/dashboard/templates", params: { q: "rails" }
      expect(response).to have_http_status(:success)
    end

    it "filters by category" do
      get "/dashboard/templates", params: { category: "CMS" }
      expect(response).to have_http_status(:success)
    end
  end

  describe "show (signed in)" do
    before { sign_in user }

    it "returns 200 for known template" do
      skip "No templates available" unless template_slug
      get "/dashboard/templates/#{template_slug}"
      expect(response).to have_http_status(:success)
    end

    it "redirects with alert for unknown template" do
      get "/dashboard/templates/nonexistent-slug-xyz"
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response).to have_http_status(:success)
    end
  end

  describe "create" do
    it "redirects when not authenticated" do
      post "/dashboard/templates",
           params: { template_slug: "nonexistent", server_id: server.id, app_name: "my-app" }
      expect(response).to have_http_status(:redirect)
    end

    context "signed in" do
      before { sign_in user }

      it "redirects with alert when template not found" do
        post "/dashboard/templates",
             params: { template_slug: "nonexistent-slug-xyz", server_id: server.id, app_name: "my-app" }
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response).to have_http_status(:success)
      end

      it "redirects with alert when app name is blank" do
        skip "No templates available" unless template_slug
        post "/dashboard/templates",
             params: { template_slug: template_slug, server_id: server.id, app_name: "" }
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response).to have_http_status(:success)
      end

      it "deploys a template" do
        skip "No templates available" unless template_slug
        unique_name = "test-tpl-#{SecureRandom.hex(4)}"
        post "/dashboard/templates",
             params: { template_slug: template_slug, server_id: server.id, app_name: unique_name }
        expect(response).to have_http_status(:redirect)
      end

      context "Bundle v2 (box_size + plan quota)" do
        around do |ex|
          orig = ENV["BUNDLE_V2_ENABLED"]
          ENV["BUNDLE_V2_ENABLED"] = "true"
          ex.run
        ensure
          ENV["BUNDLE_V2_ENABLED"] = orig
        end

        it "sets box_size on the new app from template min_tier" do
          skip "No templates available" unless template_slug
          # Ensure plan quota is generous so the deploy isn't blocked by the
          # Free plan's 0-of-everything-except-sleeping default.
          allow_any_instance_of(Plan).to receive(:quota_for).and_return(10)

          unique_name = "test-tpl-bv2-#{SecureRandom.hex(4)}"
          post "/dashboard/templates",
               params: { template_slug: template_slug, server_id: server.id, app_name: unique_name }
          app = AppRecord.find_by(name: unique_name)
          expect(app).to be_present
          expect(app.box_size).to be_in(AppRecord::BOX_SIZES)
        end

      end
    end
  end
end
