# B4 pre-cutover gates 1+2 (housekeeping half): a wokkud agent that dies
# mid-op leaves the ServiceOp wedged at `claimed` forever — reap it to
# failed so callers/UI see a terminal state and the row isn't immortal.
# Terminal ops older than 30 days are pruned outright: their params held
# secrets at issue time (redacted at report, see ServiceOpsController),
# and the log/result audit value decays fast.
class ServiceOpJanitorJob < ApplicationJob
  queue_as :default

  # > the largest per-kind agent timeout (900s export/import) + report
  # retries. Applies to both states that can wedge an app/service lane:
  # a `claimed` op whose agent died mid-op, and a `pending` op no agent
  # ever picked up (a never-claimed op blocks the lane — and its unique
  # index makes every subsequent create! RecordNotUnique — forever).
  REAP_AFTER = 30.minutes
  PRUNE_AFTER = 30.days

  # Mirror the report controllers' redaction so a reaped row (never went
  # through #report) doesn't retain env/password/presigned URLs for 30d.
  def self.secret_keys_for(klass)
    case klass.name
    when "LifecycleOp" then Api::V1::Agent::LifecycleOpsController::SECRET_PARAM_KEYS
    when "ServiceOp"   then Api::V1::Agent::ServiceOpsController::SECRET_PARAM_KEYS
    else []
    end
  end

  def perform
    [ ServiceOp, LifecycleOp ].each { |klass| sweep!(klass) }
  end

  private

  def sweep!(klass)
    keys = self.class.secret_keys_for(klass)
    # Reap both wedged states. Per-row (not update_all) because we also
    # redact secrets off each reaped row — reaping is rare, so the cost is
    # noise. claimed reaps by claimed_at; never-claimed pending by created_at.
    reaped = 0
    reaped += reap_scope!(klass.claimed.where(claimed_at: ...REAP_AFTER.ago),
                          "reaped", "agent never reported (crashed or unreachable)", keys)
    reaped += reap_scope!(klass.pending.where(created_at: ...REAP_AFTER.ago),
                          "reaped_pending", "no agent ever claimed it", keys)
    Rails.logger.info("[ServiceOpJanitorJob] reaped #{reaped} wedged #{klass.name} op(s)") if reaped.positive?

    pruned = klass.where(status: %i[succeeded failed])
                  .where(finished_at: ...PRUNE_AFTER.ago).delete_all
    Rails.logger.info("[ServiceOpJanitorJob] pruned #{pruned} terminal #{klass.name} op(s)") if pruned.positive?

    redact_stale_tenant_keys! if klass == ServiceOp
  end

  # meilisearch tenant.provision RESULTS carry the minted api keys (params
  # redaction doesn't cover results). The consumer strips them right after
  # composing env vars; this covers the crash-between-report-and-consume
  # window so a key never sits at rest until the 30-day prune.
  RESULT_SECRET_KEYS = %w[api_key api_key_ro].freeze

  def redact_stale_tenant_keys!
    ServiceOp.where(kind: "tenant.provision", status: :succeeded)
             .where(finished_at: ...1.hour.ago)
             .where("result ?| array[:keys]", keys: RESULT_SECRET_KEYS)
             .find_each do |op|
      op.update_columns(result: redact(op.result, RESULT_SECRET_KEYS), updated_at: Time.current)
    end
  end

  def reap_scope!(scope, code, reason, keys)
    count = 0
    scope.find_each do |op|
      op.update_columns(
        status: op.class.statuses[:failed],
        error: "reaped: #{reason}",
        error_code: code,
        finished_at: Time.current,
        params: redact(op.params, keys),
        updated_at: Time.current
      )
      count += 1
    end
    count
  end

  def redact(params, keys)
    return params if keys.blank?
    params.to_h.map { |k, v| [ k, keys.include?(k.to_s) ? "[REDACTED]" : v ] }.to_h
  end
end
