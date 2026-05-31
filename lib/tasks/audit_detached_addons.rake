namespace :phase2 do
  desc "List apps with > 1 linked database (affected by 1-app-1-DB consolidation)"
  task audit_detached_addons: :environment do
    affected = AppRecord.joins(:database_services).group(:id).having("count(database_services.id) > 1")
    if affected.empty?
      puts "✓ All apps have at most 1 linked database. Safe to enforce."
    else
      puts "⚠ #{affected.count} apps with multiple linked databases:"
      affected.includes(:database_services, :team).find_each do |app|
        puts "  - #{app.team.name} / #{app.name} (#{app.database_services.count} dbs: #{app.database_services.pluck(:name).join(', ')})"
      end
      puts ""
      puts "Notify these users 7 days before enforcement; pick a primary;"
      puts "archive others read-only for 30 days, then drop."
    end
  end
end
