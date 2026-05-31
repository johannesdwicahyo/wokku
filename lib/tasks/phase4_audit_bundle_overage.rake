# One-shot audit. After the 2026-05-29 Solo gift went out to 27 users, we
# need to know who is over their plan's bundle entitlement so we can pick
# an enforcement path. Reports per user:
#   * plan + bundle caps (DB / Redis / MinIO)
#   * count of dedicated DB containers by service_type
#   * Postgres bytes used vs db_bundle_mb (per the latest stats snapshot)
#   * "verdict": within | over_count | over_size | both
#
# Runs read-only. No writes, no side effects, safe to re-run.
#
#   bin/kamal-write "bin/rails phase4:audit_bundle_overage"
#   bin/kamal-write "bin/rails phase4:audit_bundle_overage" CSV=1
namespace :phase4 do
  desc "Audit: who's over their plan-bundle entitlement after the gift?"
  task audit_bundle_overage: :environment do
    plans = Plan.all.index_by(&:key)
    rows = []

    User
      .joins(:plan)
      .where.not(deleted_at: nil)
      .or(User.joins(:plan).where(deleted_at: nil))
      .includes(:plan, :app_records)
      .find_each do |user|
        plan = user.plan
        next if plan.nil?

        team = user.teams.first
        next if team.nil?

        # All dedicated DB containers attached to any app in this user's
        # primary team. shared: false (or NULL) means "this is a dokku-
        # postgres / -redis / -memcached container", not a shared-tenant
        # row. We exclude orphans.
        dbs = DatabaseService
                .joins(:app_records)
                .where(app_records: { team_id: team.id })
                .where(shared: [ false, nil ])
                .distinct

        by_type = dbs.group(:service_type).count

        # Bundle caps (NULL on free plan rows → treat as zero MB / GB).
        db_cap_mb     = plan.db_bundle_mb.to_i
        redis_cap_mb  = plan.redis_bundle_mb.to_i
        minio_cap_gb  = plan.minio_bundle_gb.to_i

        # Postgres size: sum of latest DatabaseStatsSnapshot.db_size_bytes
        # across the user's dedicated postgres containers. Snapshots come
        # from DatabaseStatsCollectorJob every 5 min.
        pg_dbs   = dbs.where(service_type: "postgres")
        pg_bytes = pg_dbs.map { |db| db.stats_snapshots.order(recorded_at: :desc).first&.db_size_bytes.to_i }.sum
        pg_mb    = (pg_bytes / 1024.0 / 1024.0).round(1)

        pg_count    = by_type["postgres"].to_i
        redis_count = by_type["redis"].to_i
        memcache_count = by_type["memcached"].to_i
        mongo_count = by_type["mongo"].to_i + by_type["mongodb"].to_i
        mysql_count = by_type["mysql"].to_i + by_type["mariadb"].to_i

        # Verdicts. Bundle expects ONE DB + ONE Redis per plan.
        verdicts = []
        verdicts << "pg_count(#{pg_count})>1" if pg_count > 1
        verdicts << "redis_count(#{redis_count})>1" if redis_count > 1
        verdicts << "pg_size(#{pg_mb}mb > #{db_cap_mb}mb)" if db_cap_mb.positive? && pg_mb > db_cap_mb
        verdicts << "legacy_addon(#{memcache_count}mc/#{mongo_count}mg/#{mysql_count}mysql)" if (memcache_count + mongo_count + mysql_count).positive?

        rows << {
          email:        user.email,
          plan:         plan.key,
          apps:         user.app_records.count,
          pg_count:     pg_count,
          pg_size_mb:   pg_mb,
          pg_cap_mb:    db_cap_mb,
          redis_count:  redis_count,
          memcache:     memcache_count,
          mongo:        mongo_count,
          mysql:        mysql_count,
          verdict:      verdicts.empty? ? "within" : verdicts.join(" + ")
        }
      end

    puts "phase4:audit_bundle_overage"
    puts "─" * 110
    puts "Users surveyed: #{rows.size}"
    puts
    puts "  Bundle entitlement per plan (DB MB / Redis MB / MinIO GB):"
    %w[free solo pro team].each do |k|
      p = plans[k]
      next unless p
      puts "    #{k.ljust(6)} → #{p.db_bundle_mb.to_i.to_s.rjust(6)} mb · #{p.redis_bundle_mb.to_i.to_s.rjust(5)} mb · #{p.minio_bundle_gb.to_i.to_s.rjust(3)} gb"
    end
    puts
    fmt = "  %-36s %-5s %5s %8s %8s %5s %4s %4s %4s  %s"
    puts (fmt % %w[email plan apps pg_n pg_mb cap r_n mc mg verdict])
    puts "  " + ("─" * 108)
    rows.sort_by { |r| [ -(r[:verdict] == "within" ? 0 : 1), r[:email] ] }.each do |r|
      puts (fmt % [
        r[:email].first(36),
        r[:plan],
        r[:apps],
        r[:pg_count],
        r[:pg_size_mb],
        r[:pg_cap_mb],
        r[:redis_count],
        r[:memcache],
        r[:mongo],
        r[:verdict]
      ])
    end

    over = rows.count { |r| r[:verdict] != "within" }
    puts
    puts "  Over-bundle users: #{over} / #{rows.size}"
    puts "  Within-bundle:     #{rows.size - over}"

    if ENV["CSV"].to_s.downcase.in?(%w[1 true yes on])
      require "csv"
      out = Rails.root.join("tmp", "bundle_overage_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv")
      CSV.open(out, "w") do |csv|
        csv << rows.first.keys
        rows.each { |r| csv << r.values }
      end
      puts
      puts "  CSV written: #{out}"
    end
  end
end
