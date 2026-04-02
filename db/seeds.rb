if Rails.env.development? || Rails.env.test?
  password = "password123456"
  admin = User.find_or_create_by!(email: "admin@wokku.dev") do |u|
    u.password = password
    u.role = :admin
  end
  puts "Created admin user: admin@wokku.dev / #{password}"
else
  admin_email = ENV.fetch("ADMIN_EMAIL") { raise "ADMIN_EMAIL required for production seeds" }
  admin_password = ENV.fetch("ADMIN_PASSWORD") { raise "ADMIN_PASSWORD required for production seeds" }
  admin = User.find_or_create_by!(email: admin_email) do |u|
    u.password = admin_password
    u.role = :admin
  end
  puts "Created admin user: #{admin_email}"
end

team = Team.find_or_create_by!(name: "Default", owner: admin)
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end
puts "Created default team: Default"

if Wokku.ee?
  # Dyno Tiers — container sizes with vCPU and included storage
  # Hourly rate calculated from monthly: cents_per_hour = dollars_per_month * 100 / 730
  DynoTier.find_or_create_by!(name: "free") { |t| t.memory_mb = 256; t.cpu_shares = 0.15; t.price_cents_per_hour = 0; t.sleeps = true }
  DynoTier.find_or_create_by!(name: "basic") { |t| t.memory_mb = 512; t.cpu_shares = 0.3; t.price_cents_per_hour = 0.2055; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "standard") { |t| t.memory_mb = 1024; t.cpu_shares = 0.5; t.price_cents_per_hour = 0.5479; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "performance") { |t| t.memory_mb = 2048; t.cpu_shares = 1.0; t.price_cents_per_hour = 1.0959; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "performance-2x") { |t| t.memory_mb = 4096; t.cpu_shares = 2.0; t.price_cents_per_hour = 2.0548; t.sleeps = false }

  puts "Created dyno tiers: free ($0), basic ($1.50), standard ($4), performance ($8), performance-2x ($15)"

  # Service Tiers — Postgres/MySQL/MariaDB
  # Pricing: mini=free, basic=$1/mo, standard=$4/mo
  %w[postgres mysql mariadb].each do |db_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: db_type) { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 1, connections: 20 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: db_type) { |t| t.price_cents_per_hour = 0.137; t.spec = { storage_gb: 10, connections: 50, backups: "daily" } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: db_type) { |t| t.price_cents_per_hour = 0.5479; t.spec = { storage_gb: 50, connections: 120, backups: "daily" } }
  end

  # Service Tiers — Redis/Memcached
  # Pricing: mini=free, basic=$0.50/mo
  %w[redis memcached].each do |cache_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: cache_type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 25 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: cache_type) { |t| t.price_cents_per_hour = 0.0685; t.spec = { memory_mb: 100 } }
  end

  # Service Tiers — Elasticsearch
  # Pricing: basic=$4/mo, standard=$10/mo
  ServiceTier.find_or_create_by!(name: "basic", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 0.5479; t.spec = { memory_mb: 512, storage_gb: 5 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 1.3699; t.spec = { memory_mb: 1024, storage_gb: 20 } }

  # Service Tiers — MongoDB/RabbitMQ/NATS
  # Pricing: mini=free, basic=$2/mo, standard=$6/mo
  %w[mongodb rabbitmq nats].each do |type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 64 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: type) { |t| t.price_cents_per_hour = 0.274; t.spec = { memory_mb: 256 } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: type) { |t| t.price_cents_per_hour = 0.8219; t.spec = { memory_mb: 1024 } }
  end

  # Service Tiers — Meilisearch
  # Pricing: mini=free, basic=$2/mo, standard=$6/mo
  ServiceTier.find_or_create_by!(name: "mini", service_type: "meilisearch") { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 128 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: "meilisearch") { |t| t.price_cents_per_hour = 0.274; t.spec = { memory_mb: 512 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "meilisearch") { |t| t.price_cents_per_hour = 0.8219; t.spec = { memory_mb: 2048 } }

  # Service Tiers — ClickHouse
  # Pricing: basic=$4/mo, standard=$10/mo (heavier, analytics workloads)
  ServiceTier.find_or_create_by!(name: "basic", service_type: "clickhouse") { |t| t.price_cents_per_hour = 0.5479; t.spec = { memory_mb: 512, storage_gb: 10 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "clickhouse") { |t| t.price_cents_per_hour = 1.3699; t.spec = { memory_mb: 2048, storage_gb: 50 } }

  puts "Created service tiers for all database types"

  # Billing Plans (legacy, kept for backward compat)
  Plan.find_or_create_by!(name: "free") { |p| p.max_apps = 999; p.max_dynos = 999; p.max_databases = 999; p.price_cents_per_month = 0; p.stripe_price_id = nil }

  puts "Created default billing plan"
end
