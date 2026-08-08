require "rails_helper"

RSpec.describe "Api::V1::Meta", type: :request do
  it "returns version info with no authentication required" do
    get "/api/v1/meta"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include(
      "api_version" => Rails.application.config.x.api_version,
      "min_cli_version" => Api::V1::MetaController::MIN_CLI_VERSION,
      "min_mcp_version" => Api::V1::MetaController::MIN_MCP_VERSION
    )
    expect(body["server_time"]).to be_present
    expect { Time.iso8601(body["server_time"]) }.not_to raise_error
    expect(body["client"]).to eq(
      "type" => nil, "version" => nil, "min_supported" => nil, "outdated" => false
    )
  end

  it "reports an outdated CLI client" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "cli", "X-Wokku-Client-Version" => "0.4.0" }

    body = response.parsed_body
    expect(body["client"]).to eq(
      "type" => "cli", "version" => "0.4.0", "min_supported" => "0.5.0", "outdated" => true
    )
  end

  it "reports an up-to-date MCP client at exactly the minimum (equal is not outdated)" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "mcp", "X-Wokku-Client-Version" => "1.2.0" }

    body = response.parsed_body
    expect(body["client"]).to eq(
      "type" => "mcp", "version" => "1.2.0", "min_supported" => "1.2.0", "outdated" => false
    )
  end

  it "reports a CLI client above the minimum as not outdated" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "cli", "X-Wokku-Client-Version" => "0.9.0" }

    body = response.parsed_body
    expect(body["client"]).to eq(
      "type" => "cli", "version" => "0.9.0", "min_supported" => "0.5.0", "outdated" => false
    )
  end

  it "does not flag an unknown client type as outdated, even with a version header" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "dashboard", "X-Wokku-Client-Version" => "0.0.1" }

    body = response.parsed_body
    expect(body["client"]).to eq(
      "type" => "dashboard", "version" => "0.0.1", "min_supported" => nil, "outdated" => false
    )
  end

  it "tolerates an unparseable version string without raising" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "cli", "X-Wokku-Client-Version" => "not-a-version" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["client"]).to eq(
      "type" => "cli", "version" => "not-a-version", "min_supported" => "0.5.0", "outdated" => false
    )
  end

  it "is case-insensitive on the client type header" do
    get "/api/v1/meta", headers: { "X-Wokku-Client" => "CLI", "X-Wokku-Client-Version" => "0.4.0" }

    body = response.parsed_body
    expect(body["client"]).to include("type" => "cli", "outdated" => true)
  end
end
