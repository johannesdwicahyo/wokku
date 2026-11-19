# Second step of a web sign-in for a 2FA user (see TwoFactorSignIn).
# Wrong codes count against Devise lockable, like wrong passwords.
class Users::TwoFactorChallengesController < ApplicationController
  include TwoFactorSignIn

  before_action :load_pending_user

  def show
  end

  def create
    unless @user.active_for_authentication?
      return abandon(I18n.t("devise.failure.#{@user.inactive_message}", default: I18n.t("devise.failure.locked")))
    end

    if @user.valid_for_authentication? { @user.consume_second_factor!(params[:code]) }
      remember = session[:two_factor_remember]
      clear_pending_two_factor
      @user.remember_me = true if remember
      sign_in(@user, event: :authentication)
      redirect_to after_sign_in_path_for(@user), notice: I18n.t("devise.sessions.signed_in")
    elsif @user.access_locked?
      abandon(I18n.t("devise.failure.locked"))
    else
      flash.now[:alert] = I18n.t("auth.two_factor_challenge.invalid")
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_pending_user
    started = session[:two_factor_started_at].to_i
    @user = User.find_by(id: session[:two_factor_user_id]) if session[:two_factor_user_id]
    if @user.nil? || !@user.two_factor_enabled?
      clear_pending_two_factor
      redirect_to new_user_session_path
    elsif Time.current.to_i - started > PENDING_TTL
      abandon(I18n.t("auth.two_factor_challenge.expired"))
    end
  end

  def abandon(message)
    clear_pending_two_factor
    redirect_to new_user_session_path, alert: message
  end
end
