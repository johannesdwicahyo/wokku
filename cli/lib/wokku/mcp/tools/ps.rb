require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "scale_app",
  description: "Scale processes for a Wokku app",
  input_schema: {
    type: "object",
    properties: {
      app_id: { type: "integer", description: "App ID" },
      scaling: { type: "object", description: "Process type to count mapping, e.g. {web: 2, worker: 1}" }
    },
    required: ["app_id", "scaling"]
  }
) do |args|
  client = Wokku::ApiClient.new
  client.patch("apps/#{args['app_id']}/ps", { scaling: args["scaling"] })
  "Scaled successfully"
end

Wokku::MCP::Server.register_tool(
  "restart_app",
  description: "Restart a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: ["app_id"]
  }
) do |args|
  client = Wokku::ApiClient.new
  client.post("apps/#{args['app_id']}/restart")
  "App restarted"
end
