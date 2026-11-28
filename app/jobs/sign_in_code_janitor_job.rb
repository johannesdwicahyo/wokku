# Daily: drop email sign-in codes older than 2 days. Each code lives 10
# minutes; the 48 h covers the daily-cap lookback (SignInCodes::Issue.paused?:
# 3 locks in the 24 h before a lock that itself pauses for 24 h).
class SignInCodeJanitorJob < ApplicationJob
  queue_as :default

  def perform
    SignInCode.where(created_at: ...(2 * SignInCodes::Issue::PAUSE_FOR).ago).delete_all
  end
end
