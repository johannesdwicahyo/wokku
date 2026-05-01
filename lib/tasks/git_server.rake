namespace :git do
  desc "Start the Git SSH server"
  task server: :environment do
    Git::Server.new(
      host: ENV.fetch("GIT_HOST", "0.0.0.0"),
      port: ENV.fetch("GIT_PORT", 2222).to_i
    ).start
  end
end
