admin = User.find_or_create_by!(email: "admin@wokku.local") do |u|
  u.password = "password123456"
  u.role = :admin
end
team = Team.find_or_create_by!(name: "Default", owner: admin)
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end

puts "Created admin user: admin@wokku.local / password123456"
puts "Created default team: Default"

# Dyno Tiers
DynoTier.find_or_create_by!(name: "eco") { |t| t.memory_mb = 256; t.cpu_shares = 25; t.price_cents_per_month = 0; t.sleeps = true }
DynoTier.find_or_create_by!(name: "basic") { |t| t.memory_mb = 512; t.cpu_shares = 50; t.price_cents_per_month = 500; t.sleeps = false }
DynoTier.find_or_create_by!(name: "standard-1x") { |t| t.memory_mb = 1024; t.cpu_shares = 100; t.price_cents_per_month = 1200; t.sleeps = false }
DynoTier.find_or_create_by!(name: "standard-2x") { |t| t.memory_mb = 2048; t.cpu_shares = 200; t.price_cents_per_month = 2500; t.sleeps = false }
DynoTier.find_or_create_by!(name: "performance") { |t| t.memory_mb = 4096; t.cpu_shares = 400; t.price_cents_per_month = 5000; t.sleeps = false }

puts "Created dyno tiers: eco, basic, standard-1x, standard-2x, performance"

# Billing Plans
Plan.find_or_create_by!(name: "free") { |p| p.max_apps = 5; p.max_dynos = 10; p.max_databases = 1; p.price_cents_per_month = 0; p.stripe_price_id = nil }
Plan.find_or_create_by!(name: "hobby") { |p| p.max_apps = 10; p.max_dynos = 25; p.max_databases = 5; p.price_cents_per_month = 700; p.stripe_price_id = "price_hobby" }
Plan.find_or_create_by!(name: "professional") { |p| p.max_apps = 50; p.max_dynos = 100; p.max_databases = 20; p.price_cents_per_month = 2500; p.stripe_price_id = "price_pro" }
Plan.find_or_create_by!(name: "enterprise") { |p| p.max_apps = 999; p.max_dynos = 999; p.max_databases = 100; p.price_cents_per_month = 10000; p.stripe_price_id = "price_enterprise" }

puts "Created billing plans: free, hobby, professional, enterprise"
