# Sentry Crons check-in wrapper for scheduled jobs.
#
# Usage:
#   class MyJob < ApplicationJob
#     include SentryMonitored
#     monitor_with_sentry "my-job-slug"
#
#     def perform; ...; end
#   end
#
# Each tick fires three calls to Sentry:
#   - in_progress when the job starts
#   - ok if perform returns
#   - error if perform raises
#
# Configure the monitor (schedule + alert rules) in the Sentry dashboard
# under "Crons" using the same slug. Sentry will alert if it doesn't
# see an `ok` check-in within the expected window — that's the whole
# point: we find out within an hour if a recurring job stops firing,
# not a week later from billing complaints.
#
# No-ops gracefully if Sentry isn't configured (dev / test).
module SentryMonitored
  extend ActiveSupport::Concern

  class_methods do
    def monitor_with_sentry(slug)
      @sentry_monitor_slug = slug.to_s
    end

    def sentry_monitor_slug
      @sentry_monitor_slug
    end
  end

  included do
    around_perform do |_job, block|
      slug = self.class.sentry_monitor_slug
      if slug && defined?(Sentry) && Sentry.respond_to?(:capture_check_in) && Sentry.initialized?
        check_in_id = Sentry.capture_check_in(slug, :in_progress)
        begin
          block.call
          Sentry.capture_check_in(slug, :ok, check_in_id: check_in_id)
        rescue StandardError
          Sentry.capture_check_in(slug, :error, check_in_id: check_in_id) if check_in_id
          raise
        end
      else
        block.call
      end
    end
  end
end
