# Daily: drop email sign-in codes older than a day. Each code lives 10
# minutes and SignInCodes::Issue looks back only 10 minutes.
class SignInCodeJanitorJob < ApplicationJob
  queue_as :default

  def perform
    SignInCode.where(created_at: ...1.day.ago).delete_all
  end
end
