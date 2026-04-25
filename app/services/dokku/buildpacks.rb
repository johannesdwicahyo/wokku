module Dokku
  # Wraps `dokku buildpacks:*` commands. Buildpack URLs are passed
  # verbatim to dokku — they're typed by humans (heroku/* repos), so we
  # validate format here as defense in depth and let dokku reject the
  # rest if a typo slips through.
  class Buildpacks
    URL_PATTERN = %r{\A(https?://[\w.\-/:]+|heroku/[\w\-]+)\z}

    class InvalidUrlError < StandardError; end

    def initialize(client)
      @client = client
    end

    def list(app)
      out = @client.run("buildpacks:list #{Shellwords.escape(app)}")
      out.lines.map(&:strip).reject(&:empty?)
    end

    def add(app, url, index: nil)
      ensure_url!(url)
      flag = index ? "--index #{index.to_i} " : ""
      @client.run("buildpacks:add #{flag}#{Shellwords.escape(app)} #{Shellwords.escape(url)}")
    end

    def remove(app, url)
      ensure_url!(url)
      @client.run("buildpacks:remove #{Shellwords.escape(app)} #{Shellwords.escape(url)}")
    end

    def set(app, urls)
      urls.each { |u| ensure_url!(u) }
      @client.run("buildpacks:clear #{Shellwords.escape(app)}")
      urls.each_with_index do |url, i|
        @client.run("buildpacks:add --index #{i + 1} #{Shellwords.escape(app)} #{Shellwords.escape(url)}")
      end
    end

    def clear(app)
      @client.run("buildpacks:clear #{Shellwords.escape(app)}")
    end

    private

    def ensure_url!(url)
      raise InvalidUrlError, "buildpack URL invalid: #{url.inspect}" unless url.to_s.match?(URL_PATTERN)
    end
  end
end
