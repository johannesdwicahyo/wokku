# First-boot setup (Uptime-Kuma-style): with zero users, every request
# lands here to create the admin account; once any user exists the
# routes turn into redirects. Cloud never sees it (users always exist).
class SetupController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  before_action :ensure_fresh_install!

  layout "application"

  def new
    @user = User.new
  end

  def create
    @user = User.new(setup_params.merge(role: :admin))
    if @user.save
      @user.ensure_personal_team!
      sign_in(@user)
      # Single-box onboarding: pre-register this host as the first server
      # so the connect one-liner is waiting right after admin creation.
      # (install.sh pre-registers "main" — find_or_create keeps both paths
      # converging on the same row.)
      if params[:connect_this_server] == "1"
        server = Server.find_or_create_by(name: "main") { |s| s.host = request.host }
        return redirect_to admin_server_path(server), notice: t("setup.created") if server.persisted?
      end
      redirect_to dashboard_root_path, notice: t("setup.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def setup_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def ensure_fresh_install!
    redirect_to new_user_session_path if User.exists?
  end
end
