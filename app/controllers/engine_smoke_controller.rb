# Engine smoke slice (Phase 1b): a controller defined entirely in Wokku::Engine,
# proving route→controller→view rendering crosses the engine boundary. Kept as a
# permanent CI guard for the engine request/asset path. Skips auth — it renders
# no user data and exists only as a boundary probe.
class EngineSmokeController < ActionController::Base
  layout false

  def show
  end
end
