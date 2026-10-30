# App deletion runs here, not in the request: stack.remove waits on the host
# (often tens of seconds) and kamal-proxy cuts responses at ~30 s, so the
# dashboard showed a 504 while the delete was still finishing. Each step is
# reported live to the dashboard through Apps::DeletionProgress.
class AppDestroyJob < ApplicationJob
  queue_as :default

  # A deploy or op that started after the request was accepted: wait it out.
  retry_on ::Lifecycle::Ops::Busy, wait: 1.minute, attempts: 15 do |job, _error|
    Apps::DeletionProgress.load(job.arguments.first)&.finish!(:failed)
  end

  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return unless app # already gone (double click, retry)

    progress = Apps::DeletionProgress.load(app_id) || Apps::DeletionProgress.start!(app)
    ::Apps::Destroyer.call(app, progress: progress).warnings.each { |w| Rails.logger.warn(w) }
    progress.finish!(:done)
  rescue ::Lifecycle::Ops::Busy
    raise # retry_on
  rescue StandardError
    progress&.finish!(:failed)
    raise
  end
end
