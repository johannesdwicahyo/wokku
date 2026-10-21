# frozen_string_literal: true

require "openapi_helper"

# Templates are a read-only bundled gallery (not team-owned), so there is no
# foreign-team 404 for index/show. templates.deploy creates an app in the
# caller's own team; servers are platform-shared.
RSpec.describe "API v1 templates", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:server) { servers(:one) }
  error = { "$ref" => "#/components/schemas/Error" }
  template_schema = { "$ref" => "#/components/schemas/Template" }
  plain_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }

  path "/api/v1/templates" do
    get "List gallery templates" do
      operationId "templates.list"
      tags "templates"
      security [ { bearer: [] } ]
      produces "application/json"
      parameter name: :q, in: :query, required: false, schema: { type: :string }, description: "Search name, description and tags"
      parameter name: :category, in: :query, required: false, schema: { type: :string }, description: "Category slug (ignored when q is given)"

      response "200", "templates and categories" do
        schema type: :object, required: %w[templates categories],
               properties: {
                 templates: { type: :array, items: template_schema },
                 categories: { type: :array, items: { type: :object, required: %w[name slug], properties: { name: { type: :string }, slug: { type: :string } } } }
               }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/templates/{id}" do
    parameter name: :id, in: :path, schema: { type: :string }, description: "Template slug"

    get "Show a template" do
      operationId "templates.show"
      tags "templates"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { "n8n" }

      response "200", "template" do
        schema template_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown template slug" do
        let(:id) { "no-such-template" }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/templates/deploy" do
    post "Deploy a template as a new app" do
      operationId "templates.deploy"
      tags "templates"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[slug server_id app_name],
        properties: {
          slug: { type: :string, example: "n8n" },
          server_id: { type: :string, description: "Server UUID or name" },
          app_name: { type: :string, example: "my-n8n", description: "Parameterized to a DNS-safe name" }
        }
      }
      let(:payload) { { slug: "n8n", server_id: server.id, app_name: "spec-template-app" } }

      response "201", "app created; the deploy runs in the background" do
        schema type: :object, required: %w[app deploy],
               properties: {
                 app: { type: :object, required: %w[id name status], properties: {
                   id: { type: :string, format: :uuid }, name: { type: :string }, status: { type: :string }, box_size: { type: :string, nullable: true } } },
                 deploy: { type: :object, required: %w[id status], properties: { id: { type: :string, format: :uuid }, status: { type: :string } } }
               }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "plan box quota reached (ad-hoc body)" do
        before do
          allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
          allow_any_instance_of(Api::V1::TemplatesController).to receive(:enforce_plan_quota!)
            .and_raise(PlanEnforceable::PlanQuotaError.new(size: "small", allowed: 1, requested: 2))
        end
        schema plain_error
        run_test!
      end

      response "404", "unknown template or server" do
        let(:payload) { { slug: "no-such-template", server_id: server.id, app_name: "x" } }
        schema error
        run_test!
      end

      response "409", "app name already taken on that server (already_exists)" do
        let(:payload) { { slug: "n8n", server_id: server.id, app_name: app_records(:one).name } }
        schema error
        run_test!
      end

      response "422", "blank app_name (ad-hoc body) or builder preflight refusal (typed Error)" do
        let(:payload) { { slug: "n8n", server_id: server.id, app_name: "" } }
        schema plain_error
        run_test!
      end
    end
  end
end
