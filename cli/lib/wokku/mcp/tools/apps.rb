require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "list_apps",
  description: "List all Wokku apps",
  input_schema: { type: "object", properties: {}, required: [] }
) do |_args|
  client = Wokku::ApiClient.new
  apps = client.get("apps")
  apps.map { |a| "#{a['name']} (#{a['status']})" }.join("\n")
end

Wokku::MCP::Server.register_tool(
  "create_app",
  description: "Create a new Wokku app",
  input_schema: {
    type: "object",
    properties: {
      name: { type: "string", description: "App name (lowercase alphanumeric with hyphens)" },
      server_id: { type: "integer", description: "Server ID to deploy on" }
    },
    required: ["name", "server_id"]
  }
) do |args|
  client = Wokku::ApiClient.new
  app = client.post("apps", { name: args["name"], server_id: args["server_id"] })
  "Created app: #{app['name']}"
end

Wokku::MCP::Server.register_tool(
  "destroy_app",
  description: "Destroy a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: ["app_id"]
  }
) do |args|
  client = Wokku::ApiClient.new
  client.delete("apps/#{args['app_id']}")
  "App destroyed"
end

Wokku::MCP::Server.register_tool(
  "app_info",
  description: "Get info about a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: ["app_id"]
  }
) do |args|
  client = Wokku::ApiClient.new
  app = client.get("apps/#{args['app_id']}")
  app.map { |k, v| "#{k}: #{v}" }.join("\n")
end
