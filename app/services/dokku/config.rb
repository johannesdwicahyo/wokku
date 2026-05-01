require "shellwords"

module Dokku
  class Config
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("config:show #{Shellwords.escape(app_name)}")
      parse_env(output)
    end

    # Dokku rebuilds the app on every config change unless told otherwise.
    # That can take 2–5 minutes for a Python / Ruby app and blocks the
    # API request long past any reasonable HTTP timeout, surfacing as a
    # `Net::ReadTimeout` even though the env-var was written. Default to
    # `--no-restart`; callers that need an immediate restart (rare) pass
    # `restart: true`. The dashboard surfaces a "Restart for changes to
    # take effect" hint after a config write.
    def set(app_name, vars = {}, restart: false)
      pairs = vars.map { |k, v| "#{Shellwords.escape(k.to_s)}=#{Shellwords.escape(v.to_s)}" }.join(" ")
      flag = restart ? "" : "--no-restart "
      @client.run("config:set #{flag}#{Shellwords.escape(app_name)} #{pairs}")
    end

    def unset(app_name, *keys, restart: false)
      escaped_keys = keys.map { |k| Shellwords.escape(k.to_s) }.join(" ")
      flag = restart ? "" : "--no-restart "
      @client.run("config:unset #{flag}#{Shellwords.escape(app_name)} #{escaped_keys}")
    end

    def get(app_name, key)
      @client.run("config:get #{Shellwords.escape(app_name)} #{Shellwords.escape(key.to_s)}")
    end

    private

    def parse_env(output)
      result = {}
      output.each_line do |line|
        line = line.strip
        next if line.blank? || line.start_with?("=")
        if (match = line.match(/\A(\w+):\s*(.*)\z/))
          result[match[1]] = match[2]
        end
      end
      result
    end
  end
end
