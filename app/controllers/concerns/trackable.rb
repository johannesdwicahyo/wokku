module Trackable
  extend ActiveSupport::Concern

  private

  def track(action, target: nil, metadata: {})
    return unless current_user && current_team

    Activity.log(
      user: current_user,
      team: current_team,
      action: action,
      target: target,
      metadata: metadata
    )
  end

  def current_team
    @current_team ||= current_user&.teams&.first
  end
end
