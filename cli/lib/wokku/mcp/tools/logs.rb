require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "app_logs",
  description: "Get recent logs for a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: [ "app_id" ]
  }
) do |args|
  client = Wokku::ApiClient.new
  logs = client.get("apps/#{args['app_id']}/logs")
  logs.is_a?(String) ? logs : logs.to_s
end
