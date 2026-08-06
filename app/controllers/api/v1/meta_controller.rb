module Api
  module V1
    # Unauthenticated version/capability probe. wokku CLI's `doctor` command
    # (and the MCP plugin on boot) hit this before any authenticated call to
    # learn whether they're outdated — so it inherits ActionController::API
    # directly, like Api::V1::Agent::BaseController, rather than
    # Api::V1::BaseController (no token required, nothing secret in here).
    class MetaController < ActionController::API
      include ClientVersion

      # Bump when a breaking CLI/MCP-facing API change ships. Sourced from
      # ClientVersion::MIN_VERSIONS so the compare logic and the advertised
      # minimum can never drift apart.
      MIN_CLI_VERSION = ClientVersion::MIN_VERSIONS.fetch("cli")
      MIN_MCP_VERSION = ClientVersion::MIN_VERSIONS.fetch("mcp")

      def show
        render json: {
          api_version: Rails.application.config.x.api_version,
          min_cli_version: MIN_CLI_VERSION,
          min_mcp_version: MIN_MCP_VERSION,
          server_time: Time.current.iso8601,
          client: client_version_info
        }
      end
    end
  end
end
