require "shellwords"

module Dokku
  class Logs
    def initialize(client)
      @client = client
    end

    def recent(app_name, lines: 100)
      @client.run("logs #{Shellwords.escape(app_name)} --num #{lines.to_i}")
    end

    def tail(app_name, &block)
      @client.run_streaming("logs #{Shellwords.escape(app_name)} --tail", &block)
    end
  end
end
