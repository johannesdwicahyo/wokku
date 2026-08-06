class ApplicationJob < ActiveJob::Base
  include Notifiable

  # Database deadlocks: retry with short backoff
  retry_on ActiveRecord::Deadlocked, wait: 3.seconds, attempts: 5

  # Transient SSH/network failures: exponential backoff
  retry_on Net::SSH::ConnectionTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 3
  retry_on Errno::ETIMEDOUT, wait: :polynomially_longer, attempts: 3

  # Host SSH connection errors (wraps SSH failures)
  retry_on Hosts::Ssh::ConnectionError, wait: :polynomially_longer, attempts: 3

  # Discard jobs if the underlying record is gone
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  private

  # Shared "skip-if-saturated" guard for the per-server/per-domain fan-out
  # schedulers. Counts only genuinely in-flight jobs: a failed execution
  # keeps finished_at: nil forever, so counting those let a backlog of
  # failures permanently wedge a scheduler (both MetricsPollJob and
  # HealthCheckJob froze in prod this way on 2026-06-16). Returns true when
  # the caller should skip this tick.
  def scheduler_saturated?(job_class, cap:)
    pending = SolidQueue::Job
      .where(class_name: job_class, finished_at: nil)
      .where.missing(:failed_execution)
      .count
    return false if pending < cap

    Rails.logger.warn("#{self.class.name}: #{pending} pending >= cap #{cap}; skipping tick")
    true
  end
end
