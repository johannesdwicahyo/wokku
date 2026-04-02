namespace :dynos do
  desc "Apply a dyno tier to all apps that don't have one (default: basic)"
  task :apply_defaults, [ :tier_name ] => :environment do |_t, args|
    tier_name = args[:tier_name] || "basic"
    tier = DynoTier.find_by!(name: tier_name)

    puts "Applying '#{tier_name}' tier (#{tier.memory_mb}MB, #{tier.cpu_shares} CPU) to apps without allocations..."

    apps = AppRecord.left_joins(:dyno_allocations)
                    .where(dyno_allocations: { id: nil })
                    .includes(:server)

    if apps.empty?
      puts "All apps already have dyno allocations. Nothing to do."
      next
    end

    apps.find_each do |app|
      allocation = app.dyno_allocations.create!(
        dyno_tier: tier,
        process_type: "web",
        count: 1
      )
      ApplyDynoTierJob.perform_later(allocation.id)
      puts "  #{app.name} (server: #{app.server.name}) → #{tier_name}"
    end

    puts "\nQueued #{apps.size} app(s) for resource limit application."
  end

  desc "Apply a dyno tier to ALL apps, replacing existing allocations (default: basic)"
  task :apply_all, [ :tier_name ] => :environment do |_t, args|
    tier_name = args[:tier_name] || "basic"
    tier = DynoTier.find_by!(name: tier_name)

    apps = AppRecord.includes(:server, :dyno_allocations).all

    if apps.empty?
      puts "No apps found."
      next
    end

    puts "Applying '#{tier_name}' tier (#{tier.memory_mb}MB, #{tier.cpu_shares} CPU) to all #{apps.size} app(s)..."

    apps.find_each do |app|
      allocation = app.dyno_allocations.find_or_initialize_by(process_type: "web")
      allocation.dyno_tier = tier
      allocation.count = 1 if allocation.new_record?
      allocation.save!

      ApplyDynoTierJob.perform_later(allocation.id)
      puts "  #{app.name} (server: #{app.server.name}) → #{tier_name}"
    end

    puts "\nQueued #{apps.size} app(s) for resource limit application."
  end
end
