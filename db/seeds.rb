admin = User.find_or_create_by!(email: "admin@wokku.dev") do |u|
  u.password = "password123456"
  u.role = :admin
end
team = Team.find_or_create_by!(name: "Default", owner: admin)
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end

puts "Created admin user: admin@wokku.dev / password123456"
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
  %w[postgres mysql mariadb].each do |db_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: db_type) { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 1, connections: 20 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: db_type) { |t| t.price_cents_per_hour = 0.27; t.spec = { storage_gb: 10, connections: 20, backups: "daily" } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: db_type) { |t| t.price_cents_per_hour = 1.10; t.spec = { storage_gb: 50, connections: 120, backups: "daily" } }
  end

  # Service Tiers — Redis/Memcached
  %w[redis memcached].each do |cache_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: cache_type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 25 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: cache_type) { |t| t.price_cents_per_hour = 0.14; t.spec = { memory_mb: 100 } }
  end

  # Service Tiers — Elasticsearch
  ServiceTier.find_or_create_by!(name: "basic", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 1.1; t.spec = { memory_mb: 512, storage_gb: 5 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 2.7; t.spec = { memory_mb: 1024, storage_gb: 20 } }

  # Service Tiers — MinIO (S3-compatible object storage)
  # Users buy MinIO instances for persistent storage beyond what's included in their dyno tier
  ServiceTier.find_or_create_by!(name: "mini", service_type: "minio") { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 1 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: "minio") { |t| t.price_cents_per_hour = 0.14; t.spec = { storage_gb: 5 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "minio") { |t| t.price_cents_per_hour = 0.55; t.spec = { storage_gb: 25 } }
  ServiceTier.find_or_create_by!(name: "performance", service_type: "minio") { |t| t.price_cents_per_hour = 1.37; t.spec = { storage_gb: 100 } }

  # Service Tiers — MongoDB/RabbitMQ
  %w[mongodb rabbitmq].each do |type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 64 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: type) { |t| t.price_cents_per_hour = 0.7; t.spec = { memory_mb: 256 } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: type) { |t| t.price_cents_per_hour = 2.1; t.spec = { memory_mb: 1024 } }
  end

  puts "Created service tiers for all database types"

  # Billing Plans (legacy, kept for backward compat)
  Plan.find_or_create_by!(name: "free") { |p| p.max_apps = 999; p.max_dynos = 999; p.max_databases = 999; p.price_cents_per_month = 0; p.stripe_price_id = nil }

  puts "Created default billing plan"
end
