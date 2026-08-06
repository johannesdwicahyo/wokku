module Api
  module V1
    # Retired (Track B W7 Phase 2): builds are image-based (Dockerfile /
    # nixpacks via wokkud); buildpack configuration no longer applies.
    # Routes stay mounted so old clients get the typed 410, not a 404.
    class BuildpacksController < BaseController
      def show = render_api_error(:buildpacks_retired)
      def create = render_api_error(:buildpacks_retired)
      def update = render_api_error(:buildpacks_retired)
      def destroy = render_api_error(:buildpacks_retired)
    end
  end
end
