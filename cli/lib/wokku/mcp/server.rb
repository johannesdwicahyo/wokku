require "json"

module Wokku
  module MCP
    class Server
      TOOLS = {}

      def self.register_tool(name, description:, input_schema:, &handler)
        TOOLS[name] = { description: description, input_schema: input_schema, handler: handler }
      end

      def start
        Dir[File.join(__dir__, "tools", "*.rb")].each { |f| require f }

        $stderr.puts "Wokku MCP server started"

        loop do
          line = $stdin.gets
          break unless line

          request = JSON.parse(line)
          response = handle_request(request)
          $stdout.puts(JSON.generate(response))
          $stdout.flush
        end
      end

      private

      def handle_request(request)
        case request["method"]
        when "initialize"
          {
            jsonrpc: "2.0",
            id: request["id"],
            result: {
              protocolVersion: "2024-11-05",
              capabilities: { tools: {} },
              serverInfo: { name: "wokku", version: Wokku::VERSION }
            }
          }
        when "tools/list"
          {
            jsonrpc: "2.0",
            id: request["id"],
            result: {
              tools: TOOLS.map { |name, tool|
                { name: name, description: tool[:description], inputSchema: tool[:input_schema] }
              }
            }
          }
        when "tools/call"
          tool_name = request.dig("params", "name")
          arguments = request.dig("params", "arguments") || {}
          tool = TOOLS[tool_name]

          unless tool
            return error_response(request["id"], "Unknown tool: #{tool_name}")
          end

          begin
            result = tool[:handler].call(arguments)
            {
              jsonrpc: "2.0",
              id: request["id"],
              result: { content: [ { type: "text", text: result.to_s } ] }
            }
          rescue StandardError => e
            error_response(request["id"], e.message)
          end
        else
          error_response(request["id"], "Unknown method: #{request['method']}")
        end
      end

      def error_response(id, message)
        {
          jsonrpc: "2.0",
          id: id,
          error: { code: -32601, message: message }
        }
      end
    end
  end
end
