#!/usr/bin/env ruby
# frozen_string_literal: true

# Wokku MCP Server — exposes Wokku API as MCP tools for Claude Code
#
# Usage:
#   WOKKU_API_TOKEN=your_token ruby mcp/server.rb
#
# Add to Claude Code settings (~/.claude.json):
#   {
#     "mcpServers": {
#       "wokku": {
#         "command": "ruby",
#         "args": ["path/to/mcp/server.rb"],
#         "env": { "WOKKU_API_TOKEN": "your_token" }
#       }
#     }
#   }

require "json"
require "net/http"
require "uri"

WOKKU_API_URL = ENV.fetch("WOKKU_API_URL", "https://wokku.dev/api/v1")
WOKKU_API_TOKEN = ENV.fetch("WOKKU_API_TOKEN", "")

def api_request(method, path, body = nil)
  uri = URI("#{WOKKU_API_URL}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"

  request = case method
  when :get then Net::HTTP::Get.new(uri)
  when :post then Net::HTTP::Post.new(uri)
  when :put then Net::HTTP::Put.new(uri)
  when :patch then Net::HTTP::Patch.new(uri)
  when :delete then Net::HTTP::Delete.new(uri)
  end

  request["Authorization"] = "Bearer #{WOKKU_API_TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = body.to_json if body

  response = http.request(request)
  JSON.parse(response.body) rescue response.body
end

def handle_tool(name, args)
  case name
  when "wokku_list_apps"
    api_request(:get, "/apps")
  when "wokku_get_app"
    api_request(:get, "/apps/#{args['app_id']}")
  when "wokku_create_app"
    api_request(:post, "/apps", {
      name: args["name"],
      server_id: args["server_id"],
      deploy_branch: args["deploy_branch"] || "main"
    })
  when "wokku_restart_app"
    api_request(:post, "/apps/#{args['app_id']}/restart")
  when "wokku_stop_app"
    api_request(:post, "/apps/#{args['app_id']}/stop")
  when "wokku_get_logs"
    api_request(:get, "/apps/#{args['app_id']}/logs?lines=#{args['lines'] || 100}")
  when "wokku_get_config"
    api_request(:get, "/apps/#{args['app_id']}/config")
  when "wokku_set_config"
    api_request(:put, "/apps/#{args['app_id']}/config", args["vars"])
  when "wokku_deploy_template"
    api_request(:post, "/templates/deploy", {
      slug: args["template_slug"],
      server_id: args["server_id"],
      name: args["app_name"]
    })
  when "wokku_list_domains"
    api_request(:get, "/apps/#{args['app_id']}/domains")
  when "wokku_scale_app"
    scaling = {}
    scaling["web"] = args["web"] if args["web"]
    scaling["worker"] = args["worker"] if args["worker"]
    api_request(:put, "/apps/#{args['app_id']}/ps", { scaling: scaling })
  when "wokku_delete_app"
    api_request(:delete, "/apps/#{args['app_id']}")
  when "wokku_enable_ssl"
    api_request(:post, "/apps/#{args['app_id']}/domains/#{args['domain_id']}/ssl")
  when "wokku_list_addons"
    api_request(:get, "/apps/#{args['app_id']}/addons")
  when "wokku_add_addon"
    api_request(:post, "/apps/#{args['app_id']}/addons", { service_type: args["service_type"], name: args["name"] })
  when "wokku_remove_addon"
    api_request(:delete, "/apps/#{args['app_id']}/addons/#{args['addon_id']}")
  when "wokku_list_activities"
    api_request(:get, "/activities?limit=#{args['limit'] || 20}")
  else
    { error: "Unknown tool: #{name}" }
  end
end

# MCP Protocol — stdio JSON-RPC
TOOLS = JSON.parse(File.read(File.join(__dir__, "wokku-mcp-server.json")))["tools"]

$stdout.sync = true
$stderr.sync = true

loop do
  line = $stdin.gets
  break unless line

  begin
    msg = JSON.parse(line)
    id = msg["id"]

    case msg["method"]
    when "initialize"
      $stdout.puts JSON.generate({
        jsonrpc: "2.0", id: id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "wokku", version: "1.0.0" }
        }
      })
    when "notifications/initialized"
      # No response needed
    when "tools/list"
      $stdout.puts JSON.generate({
        jsonrpc: "2.0", id: id,
        result: { tools: TOOLS }
      })
    when "tools/call"
      tool_name = msg.dig("params", "name")
      arguments = msg.dig("params", "arguments") || {}
      result = handle_tool(tool_name, arguments)
      $stdout.puts JSON.generate({
        jsonrpc: "2.0", id: id,
        result: {
          content: [ { type: "text", text: JSON.pretty_generate(result) } ]
        }
      })
    else
      $stdout.puts JSON.generate({
        jsonrpc: "2.0", id: id,
        error: { code: -32601, message: "Method not found: #{msg['method']}" }
      })
    end
  rescue => e
    $stderr.puts "Error: #{e.message}"
  end
end
