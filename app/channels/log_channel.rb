class LogChannel < ApplicationCable::Channel
  def subscribed
    @app = AppRecord.find(params[:app_id])
    stream_for @app
  end
end
