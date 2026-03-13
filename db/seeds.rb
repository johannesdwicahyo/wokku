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
