class BillingSanityCheckJob < ApplicationJob
  queue_as :default

  # Audit-only sanity check for the billing data model. Asserts the
  # invariants we want to be sure of after the resource-usage cleanup
  # work — does NOT mutate state. Intended to run hourly so anomalies
  # surface fast in Sentry while the recovery jobs (EnsureLiveAppSegments,
  # CleanupOrphanContainerSegments, etc.) handle the actual fixing.
  #
  # Invariants:
  #   1. Every live (non-crashed/non-deploying) AppRecord with a web
  #      DynoAllocation has exactly one open container ResourceUsage
  #      segment for that allocation.
  #   2. No ResourceUsage has stopped_at < started_at — that would
  #      double-debit the user (negative duration → undefined billing).
  #   3. No ResourceUsage has more than one open segment for the same
  #      resource_id_ref (would double-bill until one stops).
  #
  # Violations are logged and reported to Sentry. The job intentionally
  # never raises — a failure here shouldn't cascade and pause the recurring
  # schedule for unrelated invariants.
  def perform
    violations = []

    violations.concat(check_one_open_segment_per_live_app)
    violations.concat(check_no_negative_duration)
    violations.concat(check_no_duplicate_open_segments)

    if violations.any?
      summary = "BillingSanityCheckJob found #{violations.size} violation(s)"
      Rails.logger.warn(summary)
      violations.first(20).each { |v| Rails.logger.warn("  - #{v}") }

      if defined?(Sentry)
        Sentry.capture_message(summary, level: :warning, extra: { violations: violations.first(50) })
      end
    end

    { violations: violations.size }
  rescue StandardError => e
    Rails.logger.error("BillingSanityCheckJob errored: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    { violations: -1, error: e.message }
  end

  private

  # Apps in created/deploying/crashed state legitimately have no open
  # segment yet. Anything else (running, stopped) should have exactly
  # one open container segment per web DynoAllocation.
  def check_one_open_segment_per_live_app
    out = []
    AppRecord.where(status: %i[running stopped]).includes(dyno_allocations: :dyno_tier).find_each do |app|
      alloc = app.dyno_allocations.find_by(process_type: "web")
      next unless alloc&.dyno_tier

      open = ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil).count
      if open.zero?
        out << "AppRecord #{app.id} (#{app.name}) status=#{app.status} has DynoAllocation but no open container segment"
      elsif open > 1
        out << "AppRecord #{app.id} (#{app.name}) has #{open} open container segments — should be 1"
      end
    end
    out
  end

  def check_no_negative_duration
    ResourceUsage.where.not(stopped_at: nil)
                 .where("stopped_at < started_at")
                 .pluck(:id, :resource_type, :resource_id_ref, :started_at, :stopped_at)
                 .map { |id, type, ref, sa, ea| "ResourceUsage #{id} (#{type} #{ref}): stopped_at #{ea} < started_at #{sa}" }
  end

  def check_no_duplicate_open_segments
    ResourceUsage.where(stopped_at: nil)
                 .group(:resource_id_ref)
                 .having("count(*) > 1")
                 .count
                 .map { |ref, count| "resource_id_ref=#{ref}: #{count} concurrent open segments — should be 1" }
  end
end
