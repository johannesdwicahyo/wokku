module Dashboard
  class DevicesController < BaseController
    def show
      @user_code = params[:user_code].to_s.upcase.strip
      @device_authorization = lookup(@user_code)
    end

    def authorize
      @user_code = params[:user_code].to_s.upcase.strip
      @device_authorization = lookup(@user_code)

      if @device_authorization.nil? || @device_authorization.expired?
        flash.now[:alert] = t("dashboard.devices.invalid_or_expired", default: "Code is invalid or has expired.")
        return render :show, status: :unprocessable_entity
      end

      if params[:decision] == "approve"
        @device_authorization.approve!(current_user)
        @approved = true
      else
        @device_authorization.deny!
        @denied = true
      end
      render :show
    end

    private

    def lookup(code)
      return nil if code.blank?
      DeviceAuthorization.active.find_by(user_code: code)
    end
  end
end
