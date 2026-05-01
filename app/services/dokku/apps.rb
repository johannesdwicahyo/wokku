require "shellwords"

module Dokku
  class Apps
    def initialize(client)
      @client = client
    end

    def list
      output = @client.run("apps:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    def create(name)
      @client.run("apps:create #{Shellwords.escape(name)}")
    end

    def destroy(name)
      @client.run("apps:destroy #{Shellwords.escape(name)} --force")
    end

    def info(name)
      output = @client.run("apps:report #{Shellwords.escape(name)}")
      parse_report(output)
    end

    def rename(old_name, new_name)
      @client.run("apps:rename #{Shellwords.escape(old_name)} #{Shellwords.escape(new_name)}")
    end

    private

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
