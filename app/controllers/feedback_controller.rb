class FeedbackController < ApplicationController
  layout "landing"

  # No auth required — visitors and customers can both submit feedback.
  skip_before_action :authenticate_user!, raise: false

  def new
    @feedback = FeedbackEntry.new
  end

  def create
    @feedback = FeedbackEntry.new(feedback_params)
    @feedback.user = current_user if user_signed_in?
    @feedback.email ||= current_user&.email
    @feedback.user_agent = request.user_agent.to_s.first(500)

    if @feedback.save
      FeedbackMailer.new_submission(@feedback).deliver_later rescue nil
      redirect_to feedback_path, notice: "Thanks — we read every message."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def feedback_params
    params.require(:feedback_entry).permit(:name, :email, :message, :page)
  end
end
