# OSS-trimmed db/seeds.rb.
#
# wokku-cloud's seed file creates DynoTier + ServiceTier rows for the
# pricing engine — neither exists in OSS. The OSS app just needs:
#   - One Plan row ("free") so User.belongs_to :plan resolves
#   - An admin user
#   - A default team owned by that admin

load Rails.root.join("db/seeds/plans.rb")

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

team = Team.find_or_create_by!(name: "Default") do |t|
  t.owner = admin
end
TeamMembership.find_or_create_by!(user: admin, team: team) do |tm|
  tm.role = :admin
end
puts "Created default team: Default"
puts "OSS seed complete. Sign in at /users/sign_in"
