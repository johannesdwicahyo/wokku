# Minimal product rows for a fresh self-host (idempotent). The managed
# cloud does NOT load this — its richer db/seeds.rb owns real pricing;
# prices here are zero and dimensions mirror the cloud's resource specs.

Plan.find_or_create_by!(key: "free") do |p|
  p.name = "Free"
  p.price_usd_cents = 0
  p.price_idr = 0
  p.seats_included = 1
end

{
  "free"           => { memory_mb:  256, cpu_shares: 0.15, storage_mb:  2_048, sleeps: true  },
  "basic"          => { memory_mb:  512, cpu_shares: 0.3,  storage_mb:  5_120, sleeps: false },
  "standard"       => { memory_mb: 1024, cpu_shares: 0.5,  storage_mb: 15_360, sleeps: false },
  "performance"    => { memory_mb: 2048, cpu_shares: 1.0,  storage_mb: 30_720, sleeps: false },
  "performance-2x" => { memory_mb: 4096, cpu_shares: 2.0,  storage_mb: 61_440, sleeps: false }
}.each do |name, s|
  DynoTier.find_or_create_by!(name: name) do |t|
    t.memory_mb = s[:memory_mb]; t.cpu_shares = s[:cpu_shares]; t.storage_mb = s[:storage_mb]
    t.sleeps = s[:sleeps]
    t.monthly_price_cents = 0
    t.price_cents_per_hour = 0
  end
end

%w[postgres mysql mariadb mongodb].each do |db_type|
  { "basic"       => { memory_mb: 128, storage_gb: 1,  connections: 10, backups: "manual backup",     backup_retention: 2 },
    "standard"    => { memory_mb: 256, storage_gb: 8,  connections: 20, backups: "auto-daily backup", backup_retention: 5 },
    "performance" => { memory_mb: 512, storage_gb: 16, connections: 40, backups: "auto-daily backup", backup_retention: 10 } }.each do |tier, spec|
    ServiceTier.find_or_create_by!(name: tier, service_type: db_type) do |t|
      t.monthly_price_cents = 0
      t.price_cents_per_hour = 0
      t.spec = spec
    end
  end
end

# Admin: created by the first-boot /setup screen (Uptime-Kuma-style).
# ADMIN_PASSWORD env is the AUTOMATION path (unattended installs) — when
# set, seed the admin non-interactively; resolve by ROLE so re-seeding
# after a WOKKU_ADMIN_EMAIL change can never create a second admin.
if ENV["ADMIN_PASSWORD"].present?
  admin = User.find_by(role: :admin) || User.find_or_create_by!(email: User::ADMIN_EMAIL) do |u|
    u.password = ENV["ADMIN_PASSWORD"]
    u.role = :admin
  end
  admin.ensure_personal_team!
  if admin.email != User::ADMIN_EMAIL
    warn "wokku seeds: existing admin is #{admin.email}; WOKKU_ADMIN_EMAIL=#{User::ADMIN_EMAIL} was NOT applied (see README)"
  end
  puts "Admin: #{admin.email}#{admin.previously_new_record? ? " (created from env)" : " (existing)"}"
else
  puts "Admin: none seeded — first visit shows the /setup screen" unless User.exists?(role: :admin)
end
