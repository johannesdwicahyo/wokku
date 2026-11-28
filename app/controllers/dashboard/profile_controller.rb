module Dashboard
  class ProfileController < BaseController
    def show
    end

    def edit
    end

    def update
      if email_change_locked?
        flash.now[:alert] = t("dashboard.profile.email_change_support")
        render :show, status: :unprocessable_content
      elsif current_user.update(profile_params)
        redirect_to dashboard_profile_path, notice: "Profile updated successfully."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    # With email sign-in on, the email of an account with no provider is its
    # sign-in identity; a self-edit would be unverified and lock the owner
    # out of code sign-in. ponytail: support changes it until a
    # verify-new-email flow exists.
    def email_change_locked?
      email = params.dig(:user, :email)
      Wokku.config.email_sign_in && email && current_user.provider.blank? && current_user.apple_uid.blank? &&
        email.to_s.strip.downcase != current_user.email
    end

    def profile_params
      params.require(:user).permit(:email, :locale, :currency, :daily_debit_email_subscribed)
    end
  end
end
