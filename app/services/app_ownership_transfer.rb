# Performs the actual swap when an AppTransfer is accepted: moves the
# AppRecord (and its DBs) to the target's personal team. Under Phase 4
# invoice billing this no longer needs to rotate ResourceUsage segments —
# the cost is bundled into the new owner's plan invoice. (1.8 removed
# the legacy segment-rotation logic.)
class AppOwnershipTransfer
  Result = Struct.new(:ok?, :error, keyword_init: true)

  def self.call(app:, target_user:, at: Time.current)
    new(app: app, target_user: target_user, at: at).call
  end

  def initialize(app:, target_user:, at:)
    @app = app
    @target_user = target_user
    @at = at
  end

  def call
    target_team = @target_user.teams.first
    return Result.new(ok?: false, error: "Target user has no team. Ask them to log in once first.") if target_team.nil?
    return Result.new(ok?: false, error: "App is already owned by this user.") if @app.created_by_id == @target_user.id

    ActiveRecord::Base.transaction do
      @app.update!(team: target_team, created_by_id: @target_user.id)
    end

    Result.new(ok?: true, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(ok?: false, error: e.message)
  end
end
