module Dashboard
  class TwoFactorController < BaseController
    def show
      if current_user.otp_secret.blank?
        current_user.otp_secret = User.generate_otp_secret
        current_user.save!
      end
      @qr_code = generate_qr_code unless current_user.two_factor_enabled?
    end

    def enable
      # Already on: a stray POST must not rotate the secret under the user.
      return redirect_to(dashboard_two_factor_path) if current_user.two_factor_enabled?

      if current_user.validate_and_consume_otp!(params[:otp_code])
        current_user.otp_required_for_login = true
        show_new_codes(t("auth.two_factor.enabled_notice"))
      else
        current_user.otp_secret = User.generate_otp_secret
        current_user.save!
        @qr_code = generate_qr_code
        flash.now[:alert] = t("auth.two_factor.invalid_code")
        render :show
      end
    end

    # New set of recovery codes, proven with a current second factor.
    def regenerate_codes
      if current_user.two_factor_enabled? && second_factor_ok?
        show_new_codes(t("auth.two_factor.codes_regenerated"))
      else
        redirect_to dashboard_two_factor_path, alert: t("auth.two_factor.invalid_code")
      end
    end

    def disable
      if current_user.admin?
        redirect_to dashboard_two_factor_path, alert: t("auth.two_factor.admin_cannot_disable")
        return
      end

      if second_factor_ok?
        current_user.update!(otp_required_for_login: false, otp_secret: nil, otp_backup_codes: nil)
        redirect_to dashboard_profile_path, notice: t("auth.two_factor.disabled_notice")
      else
        redirect_to dashboard_two_factor_path, alert: t("auth.two_factor.invalid_code")
      end
    end

    private

    # Wrong codes count toward Devise lockable like a wrong password; at the
    # limit the account locks, which also ends this session.
    def second_factor_ok?
      current_user.valid_for_authentication? { current_user.consume_second_factor!(params[:otp_code]) }
    end

    # Rendered (not redirected) so the plaintext codes exist only in this
    # one response; the DB keeps hashes.
    def show_new_codes(notice)
      @recovery_codes = current_user.generate_otp_backup_codes!
      current_user.save!
      flash.now[:notice] = notice
      response.headers["Cache-Control"] = "no-store"
      render :show
    end

    def generate_qr_code
      issuer = "Wokku"
      uri = current_user.otp_provisioning_uri(current_user.email, issuer: issuer)
      qrcode = RQRCode::QRCode.new(uri)
      qrcode.as_svg(module_size: 4, standalone: true, use_path: true)
    end
  end
end
