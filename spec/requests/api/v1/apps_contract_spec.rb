# frozen_string_literal: true

require "rails_helper"

# Behaviour pins behind the apps OpenAPI contract: foreign-team apps are 404
# (not 403, which confirms the app exists), webhook secrets never leave the
# API, and every error renders the typed ApiErrors shape.
RSpec.describe "API::V1::AppsController contract", type: :request do
  let(:user) { users(:one) }
  let(:own_app) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}", "Content-Type" => "application/json" } }

  before { allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:locked?).and_return(false) }

  {
    "show" => [ :get, "" ],
    "update" => [ :patch, "" ],
    "destroy" => [ :delete, "" ],
    "restart" => [ :post, "/restart" ],
    "stop" => [ :post, "/stop" ],
    "start" => [ :post, "/start" ],
    "deploy" => [ :post, "/deploy" ],
    "run" => [ :post, "/run" ],
    "dokku" => [ :post, "/dokku" ],
    "github_connect" => [ :post, "/github_connect" ],
    "github_disconnect" => [ :delete, "/github_disconnect" ],
    "https" => [ :patch, "/https" ],
    "cdn" => [ :patch, "/cdn" ],
    "maintenance" => [ :patch, "/maintenance" ],
    "rename" => [ :patch, "/rename" ],
    "clone" => [ :post, "/clone" ],
    "lock" => [ :post, "/lock" ],
    "unlock" => [ :post, "/unlock" ],
    "transfer" => [ :post, "/transfer" ],
    "metrics" => [ :get, "/metrics" ],
    "monitor" => [ :get, "/monitor" ],
    "vitals" => [ :get, "/vitals" ]
  }.each do |action, (verb, suffix)|
    it "#{action} returns 404 for another team's app" do
      send(verb, "/api/v1/apps/#{foreign_app.id}#{suffix}", params: { enabled: true, name: "x", repo: "a/b", command: "ls" }.to_json, headers: headers)
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error_code"]).to eq("not_found")
    end
  end

  it "destroy leaves another team's app in place" do
    delete "/api/v1/apps/#{foreign_app.id}", headers: headers
    expect(AppRecord.exists?(foreign_app.id)).to be true
  end

  it "show does not expose webhook secrets" do
    own_app.update!(github_webhook_secret: "gh-secret", git_webhook_secret: "git-secret")
    get "/api/v1/apps/#{own_app.id}", headers: headers
    body = JSON.parse(response.body)
    expect(body).not_to include("github_webhook_secret", "git_webhook_secret")
    expect(body).to include("name" => own_app.name)
  end

  it "show returns null git_remote/push_instructions when no git gateway is configured" do
    orig = ENV.delete("WOKKU_GIT_HOST")
    get "/api/v1/apps/#{own_app.id}", headers: headers
    body = JSON.parse(response.body)
    expect(body).to include("git_remote" => nil, "push_instructions" => nil)
    ENV["WOKKU_GIT_HOST"] = "git.example.test"
    get "/api/v1/apps/#{own_app.id}", headers: headers
    expect(JSON.parse(response.body)["git_remote"]).to eq("git@git.example.test:#{own_app.name}")
  ensure
    orig ? ENV["WOKKU_GIT_HOST"] = orig : ENV.delete("WOKKU_GIT_HOST")
  end

  it "github_connect with no repo is a typed 422" do
    post "/api/v1/apps/#{own_app.id}/github_connect", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error_code" => "invalid_params", "retryable" => false)
  end

  it "toggle with a missing enabled is a typed 422" do
    patch "/api/v1/apps/#{own_app.id}/https", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error_code" => "invalid_params")
  end

  it "run on a never-deployed app is a typed 422 (Ops.run! unstubbed)" do
    post "/api/v1/apps/#{own_app.id}/run", params: { command: "echo hi" }.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("error_code" => "invalid_params", "retryable" => false)
    expect(JSON.parse(response.body)["error"]).to include("deploy first")
  end

  it "create over the plan quota is a typed 402" do
    allow(Wokku.config.plan_enforcer).to receive(:quota).and_return(0)
    post "/api/v1/apps", params: { name: "overquota", server_id: servers(:one).id }.to_json, headers: headers
    expect(response).to have_http_status(:payment_required)
    expect(JSON.parse(response.body)).to include("error_code" => "quota_exceeded")
  end

  # .compact dropped git_remote/push_instructions from the create response
  # when they were nil (no git gateway) — the contract requires the keys.
  it "create always returns git_remote and push_instructions (null without a gateway)" do
    orig = ENV.delete("WOKKU_GIT_HOST")
    post "/api/v1/apps", params: { name: "created-#{SecureRandom.hex(2)}", server_id: servers(:one).id }.to_json, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to include("git_remote" => nil, "push_instructions" => nil)
    expect(body).not_to have_key("warnings")
  ensure
    orig ? ENV["WOKKU_GIT_HOST"] = orig : ENV.delete("WOKKU_GIT_HOST")
  end
end
