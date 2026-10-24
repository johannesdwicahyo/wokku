module Apple
  # Sign in with Apple + APNs share one Apple key. Values come from ENV
  # (managed: .kamal/secrets); APPLE_PRIVATE_KEY is one line with literal \n.
  module Config
    module_function

    def team_id     = ENV["APPLE_TEAM_ID"].presence
    def key_id      = ENV["APPLE_KEY_ID"].presence
    def services_id = ENV["APPLE_SERVICES_ID"].presence
    def bundle_id   = ENV["APPLE_BUNDLE_ID"].presence
    def private_key = ENV["APPLE_PRIVATE_KEY"].to_s.gsub("\\n", "\n")

    def native_configured? = [ team_id, key_id, bundle_id, ENV["APPLE_PRIVATE_KEY"].presence ].all?
    def web_configured?    = [ team_id, key_id, services_id, ENV["APPLE_PRIVATE_KEY"].presence ].all?
    def audiences          = [ bundle_id, services_id ].compact
  end
end
