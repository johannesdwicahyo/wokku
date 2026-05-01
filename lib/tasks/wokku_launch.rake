namespace :wokku do
  namespace :launch do
    desc "IDR launch backfill: convert any existing USD balances to IDR and "\
         "flip every user's stored currency to 'idr'. Idempotent — safe to "\
         "re-run. Run once after enabling WOKKU_IDR_ONLY=1."
    task migrate_usd_to_idr: :environment do
      rate = 15_000
      migrated = 0
      User.where.not(currency: "idr").find_each do |user|
        idr_from_usd = (user.balance_usd_cents.to_i * rate / 100.0).round
        User.transaction do
          user.update_columns(
            currency: "idr",
            balance_idr: user.balance_idr.to_i + idr_from_usd,
            balance_usd_cents: 0
          )
        end
        migrated += 1
        puts "  #{user.email}: +Rp #{idr_from_usd.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1.')}"
      end
      puts "Migrated #{migrated} user#{'s' unless migrated == 1} to IDR."
    end
  end
end
