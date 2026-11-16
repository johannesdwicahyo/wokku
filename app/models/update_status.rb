# Singleton row behind the self-host update reminder (UpdateCheckJob).
class UpdateStatus < ApplicationRecord
  def self.current = first || create!

  def update_available?(current_version = ENV["WOKKU_VERSION"])
    Wokku::UpdateChecker.newer?(latest_version, current_version)
  end
end
