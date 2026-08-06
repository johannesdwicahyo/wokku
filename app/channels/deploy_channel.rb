class DeployChannel < ApplicationCable::Channel
  # Deploy logs stream here. Authorize before streaming: only an admin, or a
  # member of the team that owns the deploy's app, may subscribe — otherwise any
  # authenticated connection could stream any deploy's logs (env + build output)
  # by guessing/knowing a deploy id.
  def subscribed
    deploy = Deploy.find(params[:deploy_id])
    return reject unless current_user && (current_user.admin? || current_user.team_ids.include?(deploy.app_record.team_id))

    stream_for deploy
  end
end
