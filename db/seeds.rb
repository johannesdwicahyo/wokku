if Rails.env.development? || Rails.env.test?
  password = "password123456"
  admin = User.find_or_create_by!(email: "admin@wokku.cloud") do |u|
    u.password = password
    u.role = :admin
  end
  puts "Created admin user: admin@wokku.cloud / #{password}"
else
  admin_email = ENV.fetch("ADMIN_EMAIL") { raise "ADMIN_EMAIL required for production seeds" }
  admin_password = ENV.fetch("ADMIN_PASSWORD") { raise "ADMIN_PASSWORD required for production seeds" }
  admin = User.find_or_create_by!(email: admin_email) do |u|
    u.password = admin_password
    u.role = :admin
  end
  puts "Created admin user: #{admin_email}"
end

# Ensure admin has deposit balance so billing system works normally
unless admin.has_deposit_balance?
  admin.update_columns(balance_usd_cents: 1_000_00, payment_method_type: "deposit")
  puts "Set admin deposit balance: $1,000.00"
end

team = Team.find_or_create_by!(name: "Default") do |t|
  t.owner = admin
end
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end
puts "Created default team: Default"

# Dyno Tiers — container sizes with vCPU and included storage
# Pricing model: monthly_price_cents is the source of truth (USD cents).
# Hourly = monthly / 720 (kept in sync for the existing billing engine).
# Round IDR figures @ 15k IDR / USD: $1.50 = Rp 22,500, $4 = Rp 60k, etc.
{
  "free"           => { memory_mb:  256, cpu_shares: 0.15, storage_mb:  2_048, monthly_cents: 0,    sleeps: true  },
  "basic"          => { memory_mb:  512, cpu_shares: 0.3,  storage_mb:  5_120, monthly_cents: 150,  sleeps: false }, # $1.50 → Rp 22,500
  "standard"       => { memory_mb: 1024, cpu_shares: 0.5,  storage_mb: 15_360, monthly_cents: 400,  sleeps: false }, # $4   → Rp 60,000
  "performance"    => { memory_mb: 2048, cpu_shares: 1.0,  storage_mb: 30_720, monthly_cents: 800,  sleeps: false }, # $8   → Rp 120,000
  "performance-2x" => { memory_mb: 4096, cpu_shares: 2.0,  storage_mb: 61_440, monthly_cents: 1500, sleeps: false }  # $15  → Rp 225,000
}.each do |name, s|
  tier = DynoTier.find_or_create_by!(name: name) do |t|
    t.memory_mb = s[:memory_mb]; t.cpu_shares = s[:cpu_shares]; t.storage_mb = s[:storage_mb]
    t.monthly_price_cents = s[:monthly_cents]
    t.price_cents_per_hour = s[:monthly_cents].to_f / 720
    t.sleeps = s[:sleeps]
  end
  # Keep dimensions + price in sync if a prior seed left them stale.
  tier.update!(
    memory_mb: s[:memory_mb], cpu_shares: s[:cpu_shares], storage_mb: s[:storage_mb], sleeps: s[:sleeps],
    monthly_price_cents: s[:monthly_cents], price_cents_per_hour: s[:monthly_cents].to_f / 720
  )
end

puts "Created dyno tiers: free (Rp 0), basic (Rp 22,500), standard (Rp 60,000), performance (Rp 120,000), performance-2x (Rp 225,000)"

# Service Tiers — Databases (PostgreSQL, MySQL, MongoDB)
# Pricing: mini=free, basic=$1/mo, standard=$4/mo
# Backups: mini=manual only (2 cap, 1-day retention), basic=daily auto (7-day), standard=daily auto (14-day)
# Database tiers mirror dyno naming: free (shared) / basic / standard / performance.
# Pricing model: monthly_price_cents is the source of truth (USD cents).
# Hourly = monthly / 720, daily = monthly / 30. IDR_PER_USD = 15k → $1 = Rp 15k.
# DB tiers priced at clean IDR figures: 15k / 30k / 90k IDR per month.
%w[postgres mysql mongodb].each do |db_type|
  ServiceTier.find_or_create_by!(name: "basic", service_type: db_type) do |t|
    t.monthly_price_cents = 100   # Rp 15,000/mo
    t.price_cents_per_hour = 100.0 / 720
    t.spec = { memory_mb: 128, storage_gb: 1,  connections: 10, backups: "manual backup",     backup_retention: 2 }
  end
  ServiceTier.find_or_create_by!(name: "standard", service_type: db_type) do |t|
    t.monthly_price_cents = 200   # Rp 30,000/mo
    t.price_cents_per_hour = 200.0 / 720
    t.spec = { memory_mb: 256, storage_gb: 8,  connections: 20, backups: "auto-daily backup", backup_retention: 5 }
  end
  ServiceTier.find_or_create_by!(name: "performance", service_type: db_type) do |t|
    t.monthly_price_cents = 600   # Rp 90,000/mo
    t.price_cents_per_hour = 600.0 / 720
    t.spec = { memory_mb: 512, storage_gb: 16, connections: 40, backups: "auto-daily backup", backup_retention: 10 }
  end
end

# Shared free Postgres tier — logical tenant inside a per-server shared host
# container. Storage is enforced by SharedDatabaseQuotaJob (150 MB quota).
ServiceTier.find_or_create_by!(name: "shared_free", service_type: "postgres") do |t|
  t.price_cents_per_hour = 0
  t.spec = { architecture: "shared", storage_mb: 150, connections: 5, backups: "manual (on request)" }
end

# Round IDR figures (15k = $1, 30k = $2, 60k = $4, 90k = $6, 120k = $8).
# monthly_price_cents is canonical; hourly is derived (monthly / 720).
def seed_service_tier(service_type:, name:, monthly_cents:, spec:)
  ServiceTier.find_or_create_by!(name: name, service_type: service_type) do |t|
    t.monthly_price_cents = monthly_cents
    t.price_cents_per_hour = monthly_cents.to_f / 720
    t.spec = spec
  end
end

# Redis / Memcached — mini free, basic Rp 15k/mo
%w[redis memcached].each do |cache_type|
  seed_service_tier(service_type: cache_type, name: "mini",  monthly_cents: 0,   spec: { memory_mb: 25 })
  seed_service_tier(service_type: cache_type, name: "basic", monthly_cents: 100, spec: { memory_mb: 100 })
end

# Elasticsearch — basic Rp 30k, standard Rp 60k
seed_service_tier(service_type: "elasticsearch", name: "basic",    monthly_cents: 200, spec: { memory_mb: 512,  storage_gb: 5 })
seed_service_tier(service_type: "elasticsearch", name: "standard", monthly_cents: 400, spec: { memory_mb: 1024, storage_gb: 20 })

# Messaging (RabbitMQ, NATS) — mini free, basic Rp 15k, standard Rp 30k
%w[rabbitmq nats].each do |type|
  seed_service_tier(service_type: type, name: "mini",     monthly_cents: 0,   spec: { memory_mb: 64 })
  seed_service_tier(service_type: type, name: "basic",    monthly_cents: 100, spec: { memory_mb: 256 })
  seed_service_tier(service_type: type, name: "standard", monthly_cents: 200, spec: { memory_mb: 1024 })
end

# Meilisearch — mini free, basic Rp 30k, standard Rp 60k
seed_service_tier(service_type: "meilisearch", name: "mini",     monthly_cents: 0,   spec: { memory_mb: 128 })
seed_service_tier(service_type: "meilisearch", name: "basic",    monthly_cents: 200, spec: { memory_mb: 512 })
seed_service_tier(service_type: "meilisearch", name: "standard", monthly_cents: 400, spec: { memory_mb: 2048 })

# ClickHouse — heavier analytics: basic Rp 60k, standard Rp 120k
seed_service_tier(service_type: "clickhouse", name: "basic",    monthly_cents: 400, spec: { memory_mb: 512,  storage_gb: 10 })
seed_service_tier(service_type: "clickhouse", name: "standard", monthly_cents: 800, spec: { memory_mb: 2048, storage_gb: 50 })

puts "Created service tiers for all database types"

# Billing Plans (legacy, kept for backward compat)
Plan.find_or_create_by!(name: "free") { |p| p.max_apps = 999; p.max_dynos = 999; p.max_databases = 999; p.price_cents_per_month = 0; p.stripe_price_id = nil }

puts "Created default billing plan"
