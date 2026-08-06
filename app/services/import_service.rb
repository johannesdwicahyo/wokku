class ImportService
  IMPORT_COMMANDS = {
    "postgres" => "postgres:import",
    "mysql"    => "mysql:import",
    "mariadb"  => "mariadb:import",
    "mongodb"  => "mongo:import",
    "redis"    => "redis:import"
  }.freeze

  class UnsupportedTypeError < StandardError; end

  def initialize(database_service:, dump_io:)
    @db = database_service
    @dump_io = dump_io
    @server = database_service.server
  end

  # Streams a user-supplied dump file (the Heroku/pg_dump -Fc format
  # that `dokku <type>:import` accepts as stdin) into the Dokku service
  # over SSH. We never land the dump on the Rails container's disk —
  # straight stdin pipe.
  def perform!
    raise UnsupportedTypeError, "No import command for #{@db.service_type}" unless cmd = IMPORT_COMMANDS[@db.service_type]

    ssh_user = @server.ssh_user || "dokku"
    safe_name = Shellwords.escape(@db.name)
    import_cmd = ssh_user == "dokku" ? "#{cmd} #{safe_name}" : "dokku #{cmd} #{safe_name}"

    ssh_options = {
      port: @server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    ssh_options[:key_data] = [ @server.ssh_private_key ] if @server.ssh_private_key.present?

    Net::SSH.start(@server.host, ssh_user, ssh_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(import_cmd) do |_ch, success|
          raise "Failed to execute import command" unless success

          while (chunk = @dump_io.read(64 * 1024))
            ch.send_data(chunk)
          end
          ch.eof!

          ch.on_extended_data { |_, _, data| Rails.logger.warn("ImportService stderr: #{data}") }
        end
      end
      channel.wait
    end
  end
end
