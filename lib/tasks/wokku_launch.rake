namespace :wokku do
  namespace :launch do
    desc "IDR launch backfill: flip every user's stored currency to 'idr'. "\
         "Idempotent — safe to re-run. The original task also migrated "\
         "balance_idr/balance_usd_cents but those columns were dropped in "\
         "1.8 along with the deposit billing rail."
    task migrate_usd_to_idr: :environment do
      migrated = 0
      User.where.not(currency: "idr").find_each do |user|
        user.update_columns(currency: "idr")
        migrated += 1
        puts "  #{user.email}: flipped to IDR"
      end
      puts "Migrated #{migrated} user#{'s' unless migrated == 1} to IDR."
    end
  end
end
