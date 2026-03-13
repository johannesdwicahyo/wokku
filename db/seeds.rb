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
