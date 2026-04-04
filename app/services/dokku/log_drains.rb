module Dokku
  class LogDrains
    def initialize(client)
      @client = client
    end

    def add(app_name, url)
      @client.run("docker-options:add #{app_name} deploy,run \"--log-driver syslog --log-opt syslog-address=#{url}\"")
    end

    def remove(app_name)
      @client.run("docker-options:remove #{app_name} deploy,run \"--log-driver syslog\"")
    rescue StandardError
      nil
    end

    def report(app_name)
      @client.run("docker-options:report #{app_name}").to_s
    end
  end
end
