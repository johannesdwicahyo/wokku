module Dashboard
  class TwoFactorController < BaseController
    def show
      if current_user.otp_secret.blank?
        current_user.otp_secret = User.generate_otp_secret
        current_user.save!
      end
      @qr_code = generate_qr_code
    end

    def enable
      if current_user.validate_and_consume_otp!(params[:otp_code])
        current_user.update!(otp_required_for_login: true)
        redirect_to dashboard_profile_path, notice: "Two-factor authentication enabled."
      else
        current_user.otp_secret = User.generate_otp_secret
        current_user.save!
        @qr_code = generate_qr_code
        flash.now[:alert] = "Invalid code. Please try again."
        render :show
      end
    end

    def disable
      if current_user.admin?
        redirect_to dashboard_two_factor_path, alert: "Admin accounts cannot disable two-factor authentication."
        return
      end

      if current_user.validate_and_consume_otp!(params[:otp_code])
        current_user.update!(otp_required_for_login: false, otp_secret: nil)
        redirect_to dashboard_profile_path, notice: "Two-factor authentication disabled."
      else
        redirect_to dashboard_two_factor_path, alert: "Invalid code."
      end
    end

    private

    def generate_qr_code
      issuer = "Wokku"
      uri = current_user.otp_provisioning_uri(current_user.email, issuer: issuer)
      qrcode = RQRCode::QRCode.new(uri)
      qrcode.as_svg(module_size: 4, standalone: true, use_path: true)
    end
  end
end
