module Dokku
  class Logs
    def initialize(client)
      @client = client
    end

    def recent(app_name, lines: 100)
      @client.run("logs #{app_name} --num #{lines}")
    end

    def tail(app_name, &block)
      @client.run_streaming("logs #{app_name} --tail", &block)
    end
  end
end
