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
    #
    # Values are single-quote-wrapped instead of using Shellwords.escape:
    # the dokku ssh shell parses arguments via `xargs`, which doesn't
    # accept Bash's backslash-escape form for strings that contain { } "
    # — it surfaces as `xargs: unmatched single quote` once the value is
    # large or has nested JSON. Single quotes preserve everything
    # literally in both Bash and xargs; the only char needing escape is
    # the apostrophe itself, replaced with the standard '\'' dance.
    def set(app_name, vars = {}, restart: false)
      pairs = vars.map { |k, v| "#{Shellwords.escape(k.to_s)}=#{sq_escape(v.to_s)}" }.join(" ")
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

    # Wrap a value in single quotes so it survives the dokku ssh shell
    # (xargs-based) unchanged regardless of the special chars it contains.
    # The only char single quotes can't hold literally is the apostrophe
    # itself, which gets the standard '\'' substitution.
    #
    # Trailing newlines must also be stripped: dokku's ssh shell parses
    # SSH_ORIGINAL_COMMAND line by line, so a `\n` inside a single-quoted
    # value splits the command in two and xargs sees an orphan `'` on the
    # next line ("unmatched single quote"). EnvVar#strip_trailing_newlines
    # handles this on save, but other callers (and stray legacy DB rows)
    # get the same defense here.
    def sq_escape(value)
      cleaned = value.gsub(/[\r\n]+\z/, "")
      "'#{cleaned.gsub("'", "'\\\\''")}'"
    end

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
