require "wokku/api_client"

Wokku::MCP::Server.register_tool(
  "list_servers",
  description: "List all Wokku servers",
  input_schema: { type: "object", properties: {}, required: [] }
) do |_args|
  client = Wokku::ApiClient.new
  servers = client.get("servers")
  servers.map { |s| "#{s['name']} (#{s['host']}) - #{s['status']}" }.join("\n")
end
