# Reads the `X-Wokku-Client` / `X-Wokku-Client-Version` headers the CLI and
# MCP plugin send on every request, and compares against the per-type
# minimum supported version. Included in both MetaController (unauthenticated,
# no BaseController) and Api::V1::BaseController (so /doctor — Task 4 — can
# surface the same shape) — kept as its own concern rather than living on
# either controller so it isn't duplicated.
module ClientVersion
  extend ActiveSupport::Concern

  # type => minimum Gem::Version-parseable string. Unknown/absent client
  # types have no minimum (nil) and are never flagged outdated.
  MIN_VERSIONS = {
    "cli" => "0.5.0",
    "mcp" => "1.2.0"
  }.freeze

  private

  # => { type:, version:, min_supported:, outdated: }
  # Every field degrades gracefully: no headers sent, an unrecognized
  # client type, or a garbage (non-Gem::Version-parseable) version string
  # all resolve to outdated: false rather than raising.
  def client_version_info
    type = request.headers["X-Wokku-Client"].presence&.downcase
    version = request.headers["X-Wokku-Client-Version"].presence
    min_supported = MIN_VERSIONS[type]

    {
      type: type,
      version: version,
      min_supported: min_supported,
      outdated: outdated?(version, min_supported)
    }
  end

  def outdated?(version, min_supported)
    return false unless version && min_supported

    Gem::Version.new(version) < Gem::Version.new(min_supported)
  rescue ArgumentError
    # Gem::Version.new raises on unparseable strings (e.g. "not-a-version").
    false
  end
end
