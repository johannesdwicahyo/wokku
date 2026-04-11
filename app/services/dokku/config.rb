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

    def set(app_name, vars = {})
      pairs = vars.map { |k, v| "#{Shellwords.escape(k.to_s)}=#{Shellwords.escape(v.to_s)}" }.join(" ")
      @client.run("config:set #{Shellwords.escape(app_name)} #{pairs}")
    end

    def unset(app_name, *keys)
      escaped_keys = keys.map { |k| Shellwords.escape(k.to_s) }.join(" ")
      @client.run("config:unset #{Shellwords.escape(app_name)} #{escaped_keys}")
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
