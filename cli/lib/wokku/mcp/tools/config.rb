require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "get_config",
  description: "Get config vars for a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: [ "app_id" ]
  }
) do |args|
  client = Wokku::ApiClient.new
  vars = client.get("apps/#{args['app_id']}/config")
  vars.map { |k, v| "#{k}=#{v}" }.join("\n")
end

Wokku::MCP::Server.register_tool(
  "set_config",
  description: "Set config vars for a Wokku app",
  input_schema: {
    type: "object",
    properties: {
      app_id: { type: "integer", description: "App ID" },
      vars: { type: "object", description: "Key-value pairs to set" }
    },
    required: [ "app_id", "vars" ]
  }
) do |args|
  client = Wokku::ApiClient.new
  client.patch("apps/#{args['app_id']}/config", { vars: args["vars"] })
  "Config updated"
end
