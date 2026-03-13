require "json"
require "fileutils"

module Wokku
  class ConfigStore
    CONFIG_DIR = File.expand_path("~/.wokku")
    CONFIG_FILE = File.join(CONFIG_DIR, "config")

    def self.load
      return {} unless File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    rescue JSON::ParserError
      {}
    end

    def self.save(data)
      FileUtils.mkdir_p(CONFIG_DIR)
      File.write(CONFIG_FILE, JSON.pretty_generate(data))
      File.chmod(0600, CONFIG_FILE)
    end

    def self.get(key)
      load[key.to_s]
    end

    def self.set(key, value)
      config = load
      config[key.to_s] = value
      save(config)
    end

    def self.clear
      File.delete(CONFIG_FILE) if File.exist?(CONFIG_FILE)
    end

    def self.api_url
      get("api_url") || ENV["WOKKU_API_URL"]
    end

    def self.token
      get("token") || ENV["WOKKU_TOKEN"]
    end
  end
end
