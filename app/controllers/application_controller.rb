class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Localizable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActionController::InvalidAuthenticityToken, with: :stale_csrf_recovery

  # Fires after every successful Devise sign-in (form + OAuth). Checks the
  # requesting IP+UA against the user's known devices; if it's new, sends
  # an alert email and records an activity row before continuing.
  def after_sign_in_path_for(resource)
    check_new_device(resource) if resource.is_a?(User)
    super
  end

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

  def check_new_device(user)
    KnownDevice.track!(user: user, ip: request.remote_ip, user_agent: request.user_agent)
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

  # Fires when a form POST arrives with a CSRF token that doesn't match the
  # current session — almost always because the user sat idle past the
  # :timeoutable window and their first click after reload used a stale
  # token. For auth-related paths we reset the session (so the next page
  # gets a fresh token) and bounce them back to sign-in with a friendly
  # message instead of dumping them on a 422 page.
  def stale_csrf_recovery
    reset_session
    if request.path.start_with?("/users/")
      respond_to do |format|
        format.html do
          redirect_to new_user_session_path,
            alert: "Your session expired. Please sign in again."
        end
        format.json { render json: { error: "Session expired" }, status: :unprocessable_entity }
      end
    else
      # Non-auth CSRF failures are genuinely suspicious — still render 422.
      respond_to do |format|
        format.html { render file: Rails.public_path.join("422.html"), status: :unprocessable_entity, layout: false }
        format.json { render json: { error: "Invalid authenticity token" }, status: :unprocessable_entity }
      end
    end
  end
end
