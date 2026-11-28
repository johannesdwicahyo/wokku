# Daily: drop email sign-in codes older than a day (each lives 10 minutes;
# the day keeps a short trail for abuse review).
class SignInCodeJanitorJob < ApplicationJob
  queue_as :default

  def perform
    SignInCode.where(created_at: ...1.day.ago).delete_all
  end
end
