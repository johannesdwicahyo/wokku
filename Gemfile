# Test/dev Gemfile for the wokku engine. Production self-host uses
# harness/Gemfile; this one boots the harness as a test host and adds the
# test toolchain. Runtime deps mirror harness/Gemfile (the engine's
# effective deps until the gemspec curates them).
source "https://rubygems.org"

gemspec

gem "rails", "~> 8.1"
gem "pg"
gem "puma"
gem "propshaft"
gem "tailwindcss-rails"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "chartkick"
gem "view_component"
gem "commonmarker"
gem "rouge"
gem "rqrcode"
gem "devise"
gem "devise-two-factor"
gem "omniauth"
gem "omniauth-rails_csrf_protection"
gem "pundit"
gem "solid_queue"
gem "net-ssh"
gem "ed25519"
gem "bcrypt_pbkdf"
gem "sentry-ruby"
gem "sentry-rails"
gem "rack-attack"
gem "bootsnap", require: false
gem "ostruct"

group :test, :development do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "simplecov", require: false
  gem "webmock"
  gem "shoulda-matchers", "~> 6.0"
  gem "mocha"
end
