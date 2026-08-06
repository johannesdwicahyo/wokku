require "devise/orm/active_record"

Devise.setup do |config|
  config.mailer_sender = "noreply@localhost"
  config.secret_key = Rails.application.secret_key_base
end
