module Dokku
  class Config
    def initialize(client)
      @client = client
    end

    def list(app_name)
      output = @client.run("config:show #{app_name}")
      parse_env(output)
    end

    def set(app_name, vars = {})
      pairs = vars.map { |k, v| "#{k}=#{Shellwords.escape(v)}" }.join(" ")
      @client.run("config:set #{app_name} #{pairs}")
    end

    def unset(app_name, *keys)
      @client.run("config:unset #{app_name} #{keys.join(' ')}")
    end

    def get(app_name, key)
      @client.run("config:get #{app_name} #{key}")
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
