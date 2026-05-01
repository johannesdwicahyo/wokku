# Re-attribute resources that admin@ provisioned for customers, plus any
# AppRecord whose created_by user differs from team.owner. After running,
# every app's billing segments are owned by the user who actually owns the
# team (not whoever happened to type the create command).
#
# Idempotent: running twice is a no-op once the segments line up.
namespace :billing do
  desc "Re-attribute apps + segments to team owner"
  task reattribute: :environment do
    transferred = 0
    AppRecord.includes(:team).find_each do |app|
      owner = app.team&.owner
      next unless owner
      next if app.created_by_id == owner.id

      ActiveRecord::Base.transaction do
        previous = app.created_by_id
        app.update_columns(created_by_id: owner.id)

        # Close-and-reopen open segments under the new owner. Historical
        # rows stay attributed to whoever paid for them at the time.
        now = Time.current
        app.dyno_allocations.includes(:dyno_tier).find_each do |alloc|
          ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil)
                       .find_each { |u| u.stop!(at: now) }
          next unless alloc.dyno_tier
          ResourceUsage.create!(
            user_id: owner.id, resource_type: "container",
            resource_id_ref: alloc.resource_id_ref, tier_name: alloc.dyno_tier.name,
            price_cents_per_hour: alloc.dyno_tier.price_cents_per_hour * alloc.count,
            started_at: now,
            metadata: { app: app.name, process_type: alloc.process_type, count: alloc.count }
          )
        end

        app.database_services.find_each do |db|
          next if db.shared?
          ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}", stopped_at: nil)
                       .find_each { |u| u.stop!(at: now) }
          rate = db.service_tier&.hourly_price_cents.to_f
          next if rate.zero?
          ResourceUsage.create!(
            user_id: owner.id, resource_type: "database",
            resource_id_ref: "DatabaseService:#{db.id}", tier_name: db.tier_name,
            price_cents_per_hour: rate, started_at: now,
            metadata: { name: db.name, type: db.service_type, app: app.name }
          )
        end

        puts "  #{app.name}: created_by #{previous} → #{owner.id} (#{owner.email})"
        transferred += 1
      end
    end

    puts "Re-attributed #{transferred} app(s)."
  end
end
