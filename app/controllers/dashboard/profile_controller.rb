module Dashboard
  class ProfileController < BaseController
    def show
    end

    def edit
    end

    def update
      if current_user.update(profile_params)
        redirect_to dashboard_profile_path, notice: "Profile updated successfully."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:email)
    end
  end
end
