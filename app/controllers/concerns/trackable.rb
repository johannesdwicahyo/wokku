module Trackable
  extend ActiveSupport::Concern

  private

  def track(action, target: nil, metadata: {})
    user = respond_to?(:current_user, true) ? current_user : nil
    team = respond_to?(:current_team, true) ? current_team : nil
    team ||= user&.teams&.first
    return unless user && team

    Activity.log(
      user: user,
      team: team,
      action: action,
      target: target,
      metadata: metadata
    )
  end

  def current_team
    @current_team ||= current_user&.teams&.first
  end
end
