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
  # Dyno Tiers (with hourly pricing)
  DynoTier.find_or_create_by!(name: "eco") { |t| t.memory_mb = 256; t.cpu_shares = 25; t.price_cents_per_month = 0; t.price_cents_per_hour = 0; t.sleeps = true }
  DynoTier.find_or_create_by!(name: "basic") { |t| t.memory_mb = 512; t.cpu_shares = 50; t.price_cents_per_month = 300; t.price_cents_per_hour = 0.4; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "standard-1x") { |t| t.memory_mb = 1024; t.cpu_shares = 100; t.price_cents_per_month = 1000; t.price_cents_per_hour = 1.4; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "standard-2x") { |t| t.memory_mb = 2048; t.cpu_shares = 200; t.price_cents_per_month = 2000; t.price_cents_per_hour = 2.7; t.sleeps = false }
  DynoTier.find_or_create_by!(name: "performance") { |t| t.memory_mb = 4096; t.cpu_shares = 400; t.price_cents_per_month = 4000; t.price_cents_per_hour = 5.5; t.sleeps = false }

  puts "Created dyno tiers: eco, basic, standard-1x, standard-2x, performance"

  # Service Tiers — Postgres/MySQL/MariaDB
  %w[postgres mysql mariadb].each do |db_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: db_type) { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 1, connections: 20 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: db_type) { |t| t.price_cents_per_hour = 0.7; t.spec = { storage_gb: 10, connections: 20, backups: "daily" } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: db_type) { |t| t.price_cents_per_hour = 2.7; t.spec = { storage_gb: 50, connections: 120, backups: "daily" } }
    ServiceTier.find_or_create_by!(name: "premium", service_type: db_type) { |t| t.price_cents_per_hour = 10.3; t.spec = { storage_gb: 200, connections: 500, backups: "continuous" } }
  end

  # Service Tiers — Redis/Memcached
  %w[redis memcached].each do |cache_type|
    ServiceTier.find_or_create_by!(name: "mini", service_type: cache_type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 25 } }
    ServiceTier.find_or_create_by!(name: "basic", service_type: cache_type) { |t| t.price_cents_per_hour = 0.4; t.spec = { memory_mb: 100 } }
    ServiceTier.find_or_create_by!(name: "standard", service_type: cache_type) { |t| t.price_cents_per_hour = 1.1; t.spec = { memory_mb: 256 } }
    ServiceTier.find_or_create_by!(name: "premium", service_type: cache_type) { |t| t.price_cents_per_hour = 3.4; t.spec = { memory_mb: 1024 } }
  end

  # Service Tiers — Elasticsearch
  ServiceTier.find_or_create_by!(name: "basic", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 1.1; t.spec = { memory_mb: 512, storage_gb: 5 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 2.7; t.spec = { memory_mb: 1024, storage_gb: 20 } }

  # Service Tiers — MinIO
  ServiceTier.find_or_create_by!(name: "starter", service_type: "minio") { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 5 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: "minio") { |t| t.price_cents_per_hour = 0.7; t.spec = { storage_gb: 50 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: "minio") { |t| t.price_cents_per_hour = 2.7; t.spec = { storage_gb: 500 } }

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
