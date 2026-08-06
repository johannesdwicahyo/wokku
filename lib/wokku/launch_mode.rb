module Wokku
  # Launch-phase behavior flags. The ENGINE default is neutral (no
  # region-specific behavior); the managed cloud's
  # config/initializers/wokku_launch_mode.rb reopens this module at boot
  # with its own launch defaults (IDR-only Indonesia phase).
  module LaunchMode
    def self.idr_only?
      ENV.fetch("WOKKU_IDR_ONLY", "0") == "1"
    end
  end
end
