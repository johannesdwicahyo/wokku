class ApplicationJob < ActiveJob::Base
  include Notifiable

  # Database deadlocks: retry with short backoff
  retry_on ActiveRecord::Deadlocked, wait: 3.seconds, attempts: 5

  # Transient SSH/network failures: exponential backoff
  retry_on Net::SSH::ConnectionTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 3
  retry_on Errno::ETIMEDOUT, wait: :polynomially_longer, attempts: 3

  # Dokku client connection errors (wraps SSH failures)
  retry_on Dokku::Client::ConnectionError, wait: :polynomially_longer, attempts: 3

  # Discard jobs if the underlying record is gone
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound
end
