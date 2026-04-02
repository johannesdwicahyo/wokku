require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "list_domains",
  description: "List domains for a Wokku app",
  input_schema: {
    type: "object",
    properties: { app_id: { type: "integer", description: "App ID" } },
    required: [ "app_id" ]
  }
) do |args|
  client = Wokku::ApiClient.new
  domains = client.get("apps/#{args['app_id']}/domains")
  domains.map { |d| d["hostname"] }.join("\n")
end

Wokku::MCP::Server.register_tool(
  "add_domain",
  description: "Add a domain to a Wokku app",
  input_schema: {
    type: "object",
    properties: {
      app_id: { type: "integer", description: "App ID" },
      hostname: { type: "string", description: "Domain name" }
    },
    required: [ "app_id", "hostname" ]
  }
) do |args|
  client = Wokku::ApiClient.new
  client.post("apps/#{args['app_id']}/domains", { hostname: args["hostname"] })
  "Domain added: #{args['hostname']}"
end
