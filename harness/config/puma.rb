threads 3, 3
port ENV.fetch("PORT", 3000)
# Background jobs + recurring dispatch run inside puma (single-container
# self-host). Disable by unsetting SOLID_QUEUE_IN_PUMA and running
# bin/jobs separately.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
