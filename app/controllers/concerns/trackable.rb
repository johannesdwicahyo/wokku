module Trackable
  extend ActiveSupport::Concern

  private

  def track(action, target: nil, metadata: {})
    user = respond_to?(:current_user, true) ? current_user : nil
    team = respond_to?(:current_team, true) ? current_team : nil
    team ||= user&.teams&.first
    return unless user && team

    # Stamp the channel so the activity log can show MCP / CLI / API /
    # dashboard side-by-side. Inferred from the controller namespace so
    # new controllers pick it up automatically.
    enriched = { channel: default_channel }.merge((metadata || {}).symbolize_keys)

    Activity.log(
      user: user,
      team: team,
      action: action,
      target: target,
      metadata: enriched
    )
  end

  # "app" (dashboard), "api", "mcp", "cli". The CLI and MCP both hit
  # /api/v1, so they set `X-Wokku-Client: cli` / `mcp` to disambiguate.
  def default_channel
    if self.class.name.to_s.start_with?("Api::")
      header = request.headers["X-Wokku-Client"].to_s.downcase
      %w[cli mcp].include?(header) ? header : "api"
    else
      "app"
    end
  end

  def current_team
    @current_team ||= current_user&.teams&.first
  end
end
