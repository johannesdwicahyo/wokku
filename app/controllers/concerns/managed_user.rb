module ManagedUser
  extend ActiveSupport::Concern

  included do
    helper_method :managed_mode?
  end

  def managed_mode?
    # Managed mode when the EE environment variable is set
    # Power users who connect their own servers see the full UI
    ENV["WOKKU_MANAGED_MODE"] == "true"
  end
end
