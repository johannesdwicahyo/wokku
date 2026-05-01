# Performs the actual swap when an AppTransfer is accepted: moves the
# AppRecord to the target's personal team, then closes the source-owner's
# open ResourceUsage segments and reopens equivalents under the new owner
# so future hourly debits hit the new account. Frozen historical segments
# stay billed to the previous owner.
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
      rotate_app_segments
      @app.database_services.find_each { |db| rotate_db_segments(db) }
    end

    Result.new(ok?: true, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(ok?: false, error: e.message)
  end

  private

  def rotate_app_segments
    @app.dyno_allocations.includes(:dyno_tier).find_each do |alloc|
      ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil)
                   .find_each { |u| u.stop!(at: @at) }
      next unless alloc.dyno_tier
      ResourceUsage.create!(
        user_id: @target_user.id,
        resource_type: "container",
        resource_id_ref: alloc.resource_id_ref,
        tier_name: alloc.dyno_tier.name,
        price_cents_per_hour: alloc.dyno_tier.price_cents_per_hour * alloc.count,
        started_at: @at,
        metadata: { app: @app.name, process_type: alloc.process_type, count: alloc.count }
      )
    end
  end

  def rotate_db_segments(db)
    return if db.shared?
    ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}", stopped_at: nil)
                 .find_each { |u| u.stop!(at: @at) }
    rate = db.service_tier&.hourly_price_cents.to_f
    return if rate.zero?
    ResourceUsage.create!(
      user_id: @target_user.id,
      resource_type: "database",
      resource_id_ref: "DatabaseService:#{db.id}",
      tier_name: db.tier_name,
      price_cents_per_hour: rate,
      started_at: @at,
      metadata: { name: db.name, type: db.service_type, app: db.app_records.first&.name }
    )
  end
end
