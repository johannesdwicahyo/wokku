module Apps
  module Lifecycle
    # Deploy lock — refuses new deploys while held. W7 Phase 3: the lock is
    # control-plane state (app_records.deploy_locked_at), not dokku
    # apps:lock/unlock/report. lock!/unlock! keep their old return values
    # (true when locked, false when unlocked) for the controller contracts.
    class DeployLock
      def initialize(app)
        @app = app
      end

      def lock!
        return true if locked?
        @app.update!(deploy_locked_at: Time.current)
        true
      end

      def unlock!
        return false unless locked?
        @app.update!(deploy_locked_at: nil)
        false
      end

      def locked?
        @app.deploy_locked_at.present?
      end
    end
  end
end
