require "thor"
require "pastel"

require "wokku/commands/auth"
require "wokku/commands/apps"
require "wokku/commands/config"
require "wokku/commands/domains"
require "wokku/commands/addons"
require "wokku/commands/ps"
require "wokku/commands/logs"
require "wokku/commands/releases"
require "wokku/commands/servers"
require "wokku/commands/git"
require "wokku/commands/teams"
require "wokku/commands/notifications"

module Wokku
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    # ── Auth ──────────────────────────────────────────────

    desc "login", "Log in to Wokku"
    method_option :api_url, type: :string, desc: "API URL"
    def login
      Commands::Auth.new.login(api_url: options[:api_url])
    end

    desc "logout", "Log out of Wokku"
    def logout
      Commands::Auth.new.logout
    end

    desc "whoami", "Show current user"
    def whoami
      Commands::Auth.new.whoami
    end

    # ── Apps ──────────────────────────────────────────────

    desc "apps", "List all apps"
    def apps
      Commands::Apps.new.list
    end

    desc "apps:create NAME", "Create a new app"
    method_option :server, type: :string, required: true, desc: "Server ID"
    method_option :branch, type: :string, default: "main", desc: "Deploy branch"
    define_method("apps:create") do |name|
      Commands::Apps.new.create(name, server_id: options[:server], branch: options[:branch])
    end

    desc "apps:destroy APP_ID", "Destroy an app"
    method_option :confirm, type: :string, desc: "App name for confirmation"
    define_method("apps:destroy") do |app_id|
      Commands::Apps.new.destroy(app_id, confirm: options[:confirm])
    end

    desc "apps:info APP_ID", "Show app info"
    define_method("apps:info") do |app_id|
      Commands::Apps.new.info(app_id)
    end

    desc "apps:rename APP_ID NEW_NAME", "Rename an app"
    define_method("apps:rename") do |app_id, new_name|
      Commands::Apps.new.rename(app_id, new_name)
    end

    # ── Config ────────────────────────────────────────────

    desc "config APP_ID", "List config vars"
    define_method("config") do |app_id|
      Commands::Config.new.list(app_id)
    end

    desc "config:set APP_ID KEY=VALUE ...", "Set config vars"
    define_method("config:set") do |app_id, *pairs|
      Commands::Config.new.set(app_id, pairs)
    end

    desc "config:unset APP_ID KEY ...", "Unset config vars"
    define_method("config:unset") do |app_id, *keys|
      Commands::Config.new.unset(app_id, keys)
    end

    desc "config:get APP_ID KEY", "Get a single config var"
    define_method("config:get") do |app_id, key|
      Commands::Config.new.get(app_id, key)
    end

    # ── Domains ───────────────────────────────────────────

    desc "domains APP_ID", "List domains"
    define_method("domains") do |app_id|
      Commands::Domains.new.list(app_id)
    end

    desc "domains:add APP_ID DOMAIN", "Add a domain"
    define_method("domains:add") do |app_id, domain|
      Commands::Domains.new.add(app_id, domain)
    end

    desc "domains:remove APP_ID DOMAIN_ID", "Remove a domain"
    define_method("domains:remove") do |app_id, domain_id|
      Commands::Domains.new.remove(app_id, domain_id)
    end

    desc "domains:ssl APP_ID DOMAIN_ID", "Enable SSL for a domain"
    define_method("domains:ssl") do |app_id, domain_id|
      Commands::Domains.new.enable_ssl(app_id, domain_id)
    end

    # ── Addons ────────────────────────────────────────────

    desc "addons", "List all addons (databases)"
    define_method("addons") do
      Commands::Addons.new.list
    end

    desc "addons:create NAME", "Create an addon"
    method_option :type, type: :string, required: true, desc: "Service type (postgres, redis, etc.)"
    method_option :server, type: :string, required: true, desc: "Server ID"
    define_method("addons:create") do |name|
      Commands::Addons.new.create(name, service_type: options[:type], server_id: options[:server])
    end

    desc "addons:attach DATABASE_ID", "Attach addon to an app"
    method_option :app, type: :string, required: true, desc: "App ID"
    define_method("addons:attach") do |database_id|
      Commands::Addons.new.attach(database_id, app_id: options[:app])
    end

    desc "addons:detach DATABASE_ID", "Detach addon from an app"
    method_option :app, type: :string, required: true, desc: "App ID"
    define_method("addons:detach") do |database_id|
      Commands::Addons.new.detach(database_id, app_id: options[:app])
    end

    desc "addons:destroy DATABASE_ID", "Destroy an addon"
    define_method("addons:destroy") do |database_id|
      Commands::Addons.new.destroy(database_id)
    end

    desc "addons:info DATABASE_ID", "Show addon info"
    define_method("addons:info") do |database_id|
      Commands::Addons.new.info(database_id)
    end

    # ── Processes ─────────────────────────────────────────

    desc "ps APP_ID", "List processes"
    define_method("ps") do |app_id|
      Commands::Ps.new.list(app_id)
    end

    desc "ps:scale APP_ID TYPE=COUNT ...", "Scale processes"
    define_method("ps:scale") do |app_id, *pairs|
      Commands::Ps.new.scale(app_id, pairs)
    end

    desc "ps:restart APP_ID", "Restart app"
    define_method("ps:restart") do |app_id|
      Commands::Ps.new.restart(app_id)
    end

    desc "ps:stop APP_ID", "Stop app"
    define_method("ps:stop") do |app_id|
      Commands::Ps.new.stop(app_id)
    end

    desc "ps:start APP_ID", "Start app"
    define_method("ps:start") do |app_id|
      Commands::Ps.new.start(app_id)
    end

    # ── Logs ──────────────────────────────────────────────

    desc "logs APP_ID", "Show app logs"
    method_option :tail, type: :boolean, default: false, aliases: "-t", desc: "Tail logs"
    method_option :lines, type: :numeric, default: 100, aliases: "-n", desc: "Number of lines"
    define_method("logs") do |app_id|
      Commands::Logs.new.show(app_id, tail: options[:tail], lines: options[:lines])
    end

    # ── Releases ──────────────────────────────────────────

    desc "releases APP_ID", "List releases"
    define_method("releases") do |app_id|
      Commands::Releases.new.list(app_id)
    end

    desc "releases:info APP_ID RELEASE_ID", "Show release info"
    define_method("releases:info") do |app_id, release_id|
      Commands::Releases.new.info(app_id, release_id)
    end

    desc "releases:rollback APP_ID RELEASE_ID", "Rollback to a release"
    define_method("releases:rollback") do |app_id, release_id|
      Commands::Releases.new.rollback(app_id, release_id)
    end

    # ── Servers ───────────────────────────────────────────

    desc "servers", "List servers"
    define_method("servers") do
      Commands::Servers.new.list
    end

    desc "servers:add NAME", "Add a server"
    method_option :host, type: :string, required: true, desc: "Server hostname or IP"
    method_option :ssh_port, type: :numeric, default: 22, desc: "SSH port"
    method_option :team, type: :string, desc: "Team ID"
    define_method("servers:add") do |name|
      Commands::Servers.new.add(name, host: options[:host], ssh_port: options[:ssh_port], team_id: options[:team])
    end

    desc "servers:remove SERVER_ID", "Remove a server"
    define_method("servers:remove") do |server_id|
      Commands::Servers.new.remove(server_id)
    end

    desc "servers:info SERVER_ID", "Show server info"
    define_method("servers:info") do |server_id|
      Commands::Servers.new.info(server_id)
    end

    # ── Git ───────────────────────────────────────────────

    desc "git:remote APP_ID", "Add wokku git remote"
    define_method("git:remote") do |app_id|
      Commands::Git.new.add_remote(app_id)
    end

    # ── Teams ─────────────────────────────────────────────

    desc "teams:create NAME", "Create a team"
    define_method("teams:create") do |name|
      Commands::Teams.new.create(name)
    end

    desc "teams:members TEAM_ID", "List team members"
    define_method("teams:members") do |team_id|
      Commands::Teams.new.members(team_id)
    end

    desc "teams:invite TEAM_ID", "Invite a member to a team"
    method_option :email, type: :string, required: true, desc: "Email address"
    method_option :role, type: :string, default: "member", desc: "Role (admin, member)"
    define_method("teams:invite") do |team_id|
      Commands::Teams.new.invite(team_id, email: options[:email], role: options[:role])
    end

    # ── Notifications ─────────────────────────────────────

    desc "notifications", "List notification channels"
    define_method("notifications") do
      Commands::Notifications.new.list
    end

    desc "notifications:add CHANNEL", "Add a notification channel"
    method_option :target, type: :string, required: true, desc: "Target (URL, email, etc.)"
    define_method("notifications:add") do |channel|
      Commands::Notifications.new.add(channel, target: options[:target])
    end

    # ── Version ───────────────────────────────────────────

    desc "version", "Show CLI version"
    def version
      puts "wokku-cli #{Wokku::VERSION}"
    end

    map %w[--version -v] => :version
  end
end
