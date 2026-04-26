class ServerPolicy < ApplicationPolicy
  # Servers are platform infrastructure:
  # - Scope stays open so any signed-in user can pick a server when deploying
  #   an app, and `show?` stays open so users can open their own app's
  #   container console (TerminalsController uses `authorize @server, :show?`).
  # - The servers admin surface (`/dashboard/servers`, API index/show/status,
  #   sync, create, destroy, admin terminal) is gated behind `manage?` and
  #   admin-only mutating actions.

  def manage?
    user&.admin?
  end

  def index?
    manage?
  end

  def show?
    user.present?
  end

  def status?
    manage?
  end

  def sync?
    manage?
  end

  def create?
    user&.admin?
  end

  def update?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def admin_terminal?
    user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Any signed-in user sees every server so they can deploy apps to it.
      scope.all
    end
  end
end
