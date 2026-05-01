class DeployChannel < ApplicationCable::Channel
  def subscribed
    deploy = Deploy.find(params[:deploy_id])
    stream_for deploy
  end
end
