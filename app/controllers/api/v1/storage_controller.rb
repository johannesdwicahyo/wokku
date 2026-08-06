module Api
  module V1
    # Retired (Track B W7 Phase 3): persistent volumes are platform-managed
    # (Swarm mounts owned by wokkud); dokku storage:mount management no
    # longer applies. Routes stay mounted so old clients get the typed 410,
    # not a 404.
    class StorageController < BaseController
      def show = render_api_error(:storage_retired)
      def create = render_api_error(:storage_retired)
      def destroy = render_api_error(:storage_retired)
    end
  end
end
