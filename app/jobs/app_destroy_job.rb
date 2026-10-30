# App deletion runs here, not in the request: stack.remove waits on the host
# (often tens of seconds) and kamal-proxy cuts responses at ~30 s, so the
# dashboard showed a 504 while the delete was still finishing.
class AppDestroyJob < ApplicationJob
  queue_as :default

  # A deploy or op that started after the request was accepted: wait it out.
  retry_on ::Lifecycle::Ops::Busy, wait: 1.minute, attempts: 15

  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return unless app # already gone (double click, retry)

    ::Apps::Destroyer.call(app).warnings.each { |w| Rails.logger.warn(w) }
  end
end
