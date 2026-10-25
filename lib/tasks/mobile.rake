namespace :mobile do
  desc "Seed a local user + apps for the iOS UI tests (dev/test only)"
  task ui_fixture: :environment do
    raise "mobile:ui_fixture must not run in production" if Rails.env.production?

    password = "ios-ui-password-123"
    user = User.find_or_initialize_by(email: "ios-ui@wokku.test")
    user.password = password
    user.name = "iOS UI"
    user.save!
    team, = user.ensure_personal_team!
    server = Server.find_or_create_by!(name: "ios-ui-fixture") do |s|
      s.host = "127.0.0.1"
      s.port = 22
      s.ssh_user = "dokku"
      s.team = team
    end

    apps = %w[running crashed deploying sleeping stopped created].map do |status|
      AppRecord.find_or_create_by!(name: "ios-ui-#{status}", team: team) do |a|
        a.server = server
        a.creator = user
        a.deploy_branch = "main"
        a.status = status
      end.tap { |a| a.update!(status: status) }
    end
    web = apps.first

    ProcessScale.find_or_create_by!(app_record: web, process_type: "web") { |p| p.count = 1 }
    if web.deploys.count < 3
      web.deploys.destroy_all
      %i[succeeded failed succeeded].each { |s| web.deploys.create!(status: s) }
    end
    web.releases.create!(description: "v#{web.releases.count + 1}") while web.releases.count < 3
    Incident.find_or_create_by!(app_record: apps.second, resolved_at: nil) { |i| i.reason = "http_5xx"; i.started_at = 20.minutes.ago }
    unless Incident.where(app_record: web).where.not(resolved_at: nil).exists?
      Incident.create!(app_record: web, reason: "timeout", started_at: 2.days.ago, resolved_at: 2.days.ago + 15.minutes)
    end
    AlertMute.find_or_create_by!(user: user, app_record: apps.third, event: "deploy_failed")

    # Durable log lines for the Logs screen (read by /api/v1/apps/:id/logs, last 24h).
    Log.where(app_record_id: web.id).delete_all
    samples = [ "GET / 200 12ms", "GET /health 200 2ms", "POST /api/deploy 202", "GET /api/apps 200 31ms",
                "INFO worker started", "WARN slow query 480ms", "GET /assets/app.css 304 1ms",
                "POST /login 302 88ms", "ERROR worker timeout" ]
    30.times do |i|
      line = samples[i % samples.size]
      Log.create!(server: server, app_record: web, container: "ios-ui-running.web.1",
                  ts: (30 - i).minutes.ago, line: line, level: Log.detect_level(line))
    end

    puts "email=#{user.email} password=#{password}"
  end

  desc "Create/refresh the App Review demo account as a member of TEAM_ID (prints a new password)"
  task :app_review_account, [ :team_id ] => :environment do |_, args|
    team = Team.find(args[:team_id])
    password = SecureRandom.base58(20)
    user = User.find_or_initialize_by(email: "appreview@wokku.cloud")
    if user.persisted? && (user.admin? || user.teams.where.not(id: team.id).exists?)
      abort "appreview@wokku.cloud already exists as a different account (admin or other teams) — refusing to take it over"
    end
    user.password = password
    user.name = "App Review"
    user.assign_attributes(failed_attempts: 0, locked_at: nil, deletion_scheduled_at: nil) # refresh = usable again
    user.save!
    TeamMembership.find_or_create_by!(user: user, team: team) { |m| m.role = :member }
    puts "email=#{user.email} password=#{password}"
  end
end
