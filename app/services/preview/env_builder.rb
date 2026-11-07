require "uri"

module Preview
  # Env for a PR preview = the parent's env, minus the parent's database
  # credentials unless the parent opted into `database_strategy: "shared"`.
  # Previews get no database of their own yet, so "empty" (the default) and
  # "snapshot" (not built) both mean "no database" — never production's.
  class EnvBuilder
    STRIPPED_KEYS = %w[DOKKU_PROXY_PORT DOKKU_PROXY_SSL_PORT].freeze

    # Keys dropped by the last #build, so the deployer can also remove them
    # from a preview an older deploy already wrote them to.
    attr_reader :removed_keys

    def initialize(parent_app)
      @parent_app = parent_app
      @removed_keys = []
    end

    def build
      result = {}
      apply!(result, scope: "production")
      apply!(result, scope: "both")
      apply!(result, scope: "preview")
      STRIPPED_KEYS.each { |k| result.delete(k) }
      strip_database_credentials!(result) unless @parent_app.database_strategy == "shared"
      result
    end

    private

    def apply!(result, scope:)
      @parent_app.env_vars.where(scope: scope).find_each do |ev|
        result[ev.key] = ev.value
      end
    end

    # Match by VALUE, not key: add-ons write DATABASE_URL / REDIS_URL, but
    # templates copy the same DSN into other keys (NC_DB, MONGO_URI…) and
    # users split it into DB_HOST / DB_PASSWORD.
    def strip_database_credentials!(result)
      secrets = credential_values
      return if secrets.empty?

      @removed_keys = result.select { |_k, v| v.present? && secrets.any? { |s| v.include?(s) } }.keys
      @removed_keys.each { |k| result.delete(k) }
    end

    # ponytail: values under 6 chars are skipped so a short password or host
    # can't strip unrelated vars; DSN passwords are 32-hex and hosts are
    # container names, so real credentials are always longer.
    def credential_values
      @parent_app.database_services.filter_map(&:dsn).flat_map { |dsn|
        uri = URI.parse(dsn) rescue nil
        [ dsn, uri&.password && URI.decode_www_form_component(uri.password), uri&.host ]
      }.compact.reject { |s| s.length < 6 }.uniq
    end
  end
end
