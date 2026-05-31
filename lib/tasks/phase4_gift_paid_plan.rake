# Gift existing prod users free months of a paid plan. Founder decision
# 2026-05-23: gift 3 months Solo to thank early adopters and let them
# sample paid features before they're asked to pay.
#
#   bin/kamal-write "bin/rails 'phase4:gift_paid_plan[solo,3,dry]'"
#   bin/kamal-write "bin/rails 'phase4:gift_paid_plan[solo,3,live]'"
#
# Args:
#   plan_key — "solo" | "pro"
#   months   — integer (1..12 enforced)
#   mode     — "dry" | "live"
#
# Idempotent — re-runs skip any user with a `billing.plan_gifted`
# Activity row. Safe to stop and resume.
namespace :phase4 do
  desc "Gift existing Free-plan users N months of a paid plan (dry|live). " \
       "Set SKIP_EMAIL=1 to gift without sending the announcement mailer — " \
       "follow up with `phase4:announce_gift_paid_plan` later."
  task :gift_paid_plan, %i[plan_key months mode] => :environment do |_, args|
    plan_key = args[:plan_key].to_s
    months   = args[:months].to_i
    mode     = args[:mode].to_s.presence || "dry"
    skip_email = ENV["SKIP_EMAIL"].to_s.downcase.in?(%w[1 true yes on])

    abort "plan_key must be solo or pro (got #{plan_key.inspect})" unless %w[solo pro].include?(plan_key)
    abort "months must be 1..12 (got #{months.inspect})" unless months.between?(1, 12)
    abort "mode must be dry or live (got #{mode.inspect})" unless %w[dry live].include?(mode)

    plan = Plan.find_by!(key: plan_key)
    free_plan_id = Plan.find_by!(key: "free").id
    admin_email = defined?(User::ADMIN_EMAIL) ? User::ADMIN_EMAIL : "admin@wokku.cloud"
    started_at = Time.current
    trial_ends = started_at + months.months
    anchor_date = trial_ends.to_date

    puts "phase4:gift_paid_plan[#{plan_key},#{months},#{mode}]#{' SKIP_EMAIL' if skip_email}"
    puts "─────────────────────────────────"
    puts "Mode:        #{mode.upcase}#{' (NO WRITES, NO EMAILS)' if mode == 'dry'}#{' — emails suppressed' if skip_email && mode == 'live'}"
    puts "Target plan: #{plan.name} (Rp #{plan.price_idr.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse}/mo)"
    puts "Gift length: #{months} month#{'s' unless months == 1}"
    puts "Trial ends:  #{trial_ends.strftime('%Y-%m-%d %H:%M %Z')}"
    puts "Cutoff:      Free-plan users, not suspended, not admin/deleted, not previously gifted"
    puts

    candidates = User
                   .where(plan_id: free_plan_id)
                   .where.not(email: admin_email)
                   .where(deleted_at: nil)
                   .where.not(billing_status: User.billing_statuses[:suspended])

    gifted_ids = Activity.where(action: "billing.plan_gifted").distinct.pluck(:user_id)
    to_gift = candidates.where.not(id: gifted_ids)
    already_gifted = candidates.where(id: gifted_ids).count

    puts "Candidates:  #{to_gift.count} users"
    puts "Skipped:     #{already_gifted} already-gifted, #{User.where(billing_status: :suspended).count} suspended, " \
         "#{User.where(deleted_at: ..Time.current).count + User.where(email: admin_email).count} admin/deleted"
    puts

    if to_gift.empty?
      puts "Nothing to do."
      next
    end

    csv_path = nil
    if mode == "live"
      require "csv"
      csv_path = Rails.root.join("tmp", "phase4_gift_#{started_at.strftime('%Y%m%d_%H%M%S')}.csv")
      CSV.open(csv_path, "w") do |csv|
        csv << %w[user_id email signed_up plan_was anchor_after_gift trial_ends_at gifted_at status]
      end
    end

    table = []
    failures = []
    gifted = 0

    to_gift.find_each do |user|
      row = [ user.id.to_s[0, 8], user.email, user.created_at.to_date.iso8601, anchor_date.iso8601 ]

      if mode == "dry"
        table << row + [ "would_gift" ]
        next
      end

      begin
        ActiveRecord::Base.transaction do
          user.update!(
            plan_id: plan.id,
            pending_plan_id: nil,
            trial_ends_at: trial_ends,
            billing_anchor_date: anchor_date
          )

          Activity.log(
            user: user,
            team: user.teams.first,
            action: "billing.plan_gifted",
            metadata: {
              plan: plan_key,
              months: months,
              trial_ends_at: trial_ends.iso8601,
              gifted_at: started_at.iso8601,
              gifted_by: "phase4_backfill_rake"
            }
          )
        end

        unless skip_email
          BillingMailer.plan_gifted(user, plan_key, months).deliver_later if defined?(BillingMailer.plan_gifted)
        end
        gifted += 1
        CSV.open(csv_path, "a") do |csv|
          csv << [ user.id, user.email, user.created_at.iso8601, "free", anchor_date.iso8601,
                   trial_ends.iso8601, started_at.iso8601, "gifted" ]
        end
        table << row + [ "✓ gifted" ]
      rescue => e
        failures << "#{user.id} (#{user.email}): #{e.class}: #{e.message}"
        CSV.open(csv_path, "a") do |csv|
          csv << [ user.id, user.email, user.created_at.iso8601, "free", "-", "-", started_at.iso8601, "FAILED: #{e.message}" ]
        end
        table << row + [ "✗ #{e.class}" ]
        Sentry.capture_exception(e, extra: { user_id: user.id, task: "phase4:gift_paid_plan" }) if defined?(Sentry)
      end
    end

    puts "  user_id   email                                       signed_up    anchor_after_gift  status"
    puts "  ──────────────────────────────────────────────────────────────────────────────────────────────"
    table.first(50).each do |r|
      puts "  #{r[0].ljust(8)}  #{r[1].ljust(42)}  #{r[2].ljust(11)}  #{r[3].ljust(17)}  #{r[4]}"
    end
    puts "  (#{table.size - 50} more rows in CSV)" if table.size > 50 && csv_path

    puts
    if mode == "live"
      puts "Done. Gifted: #{gifted}, Failed: #{failures.size}, CSV: #{csv_path}"
      if failures.any?
        puts
        puts "Failures:"
        failures.first(10).each { |f| puts "  - #{f}" }
        puts "  (#{failures.size - 10} more)" if failures.size > 10
      end
    else
      puts "DRY RUN — no writes, no emails. Re-run with `live` to apply."
    end
  end

  # Companion to gift_paid_plan when run with SKIP_EMAIL=1. Walks every
  # user with a `billing.plan_gifted` Activity who hasn't yet received a
  # `billing.plan_gift_announced` Activity, sends the announcement
  # mailer, and logs the announcement. Idempotent — re-runs skip
  # already-announced users.
  #
  #   bin/kamal-write "bin/rails phase4:announce_gift_paid_plan[dry]"
  #   bin/kamal-write "bin/rails phase4:announce_gift_paid_plan[live]"
  desc "Email all users with a billing.plan_gifted Activity who haven't yet been announced to (dry|live)"
  task :announce_gift_paid_plan, %i[mode] => :environment do |_, args|
    mode = args[:mode].to_s.presence || "dry"
    abort "mode must be dry or live (got #{mode.inspect})" unless %w[dry live].include?(mode)

    # Dedupe by user_id. If kamal exec ran the gift task on both web and
    # worker at once, each user can have multiple billing.plan_gifted rows
    # — we still want to send the announcement only once.
    gifted_user_ids   = Activity.where(action: "billing.plan_gifted").distinct.pluck(:user_id)
    announced_user_ids = Activity.where(action: "billing.plan_gift_announced").distinct.pluck(:user_id)
    pending_user_ids  = gifted_user_ids - announced_user_ids

    puts "phase4:announce_gift_paid_plan[#{mode}]"
    puts "─────────────────────────────────"
    puts "Mode:      #{mode.upcase}#{' (NO EMAILS)' if mode == 'dry'}"
    puts "Pending:   #{pending_user_ids.size} users to email"
    puts "Already:   #{announced_user_ids.size} previously announced"
    puts

    if pending_user_ids.empty?
      puts "Nothing to announce."
      next
    end

    sent = 0
    failures = []

    pending_user_ids.each do |uid|
      user = User.find_by(id: uid)
      next unless user

      gift_act = Activity.where(action: "billing.plan_gifted", user_id: uid).order(:created_at).first
      plan_key = gift_act&.metadata.is_a?(Hash) ? gift_act.metadata["plan"].to_s.presence || "solo" : "solo"
      months   = gift_act&.metadata.is_a?(Hash) ? gift_act.metadata["months"].to_i.nonzero? || 3 : 3

      if mode == "dry"
        puts "  would email: #{user.email.ljust(42)} #{plan_key} × #{months}mo"
        next
      end

      begin
        BillingMailer.plan_gifted(user, plan_key, months).deliver_later
        Activity.log(
          user: user,
          team: user.teams.first,
          action: "billing.plan_gift_announced",
          metadata: { plan: plan_key, months: months, announced_at: Time.current.iso8601 }
        )
        sent += 1
        puts "  ✓ #{user.email}"
      rescue => e
        failures << "#{user.id} (#{user.email}): #{e.class}: #{e.message}"
        puts "  ✗ #{user.email}: #{e.message}"
        Sentry.capture_exception(e, extra: { user_id: user.id, task: "phase4:announce_gift_paid_plan" }) if defined?(Sentry)
      end
    end

    puts
    if mode == "live"
      puts "Done. Sent: #{sent}, Failed: #{failures.size}"
    else
      puts "DRY RUN — re-run with `live` to send."
    end
  end
end
