class LogChannel < ApplicationCable::Channel
  # Same guard as DeployChannel: only an admin or a member of the app's team
  # may stream its logs.
  def subscribed
    @app = AppRecord.find(params[:app_id])
    return reject unless current_user && (current_user.admin? || current_user.team_ids.include?(@app.team_id))

    stream_for @app
  end
end
