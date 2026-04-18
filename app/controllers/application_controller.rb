class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Localizable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  # Auth / account pages carry CSRF tokens tied to the session cookie. If the
  # browser re-renders a cached copy of these pages (bfcache, disk cache, or
  # a 304 revalidation after Rails has rotated the session), the embedded
  # token won't match the current session and any POST lands in
  # InvalidAuthenticityToken → 422. Force no-store on every Devise route.
  before_action :no_store_auth_pages

  private

  def no_store_auth_pages
    return unless request.path.start_with?("/users/")
    response.headers["Cache-Control"] = "no-store"
  end

  def not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def forbidden
    respond_to do |format|
      format.html { redirect_to root_path, alert: "You are not authorized to perform this action." }
      format.json { render json: { error: "Not authorized" }, status: :forbidden }
    end
  end
end
