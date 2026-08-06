module Preview
  class EnvBuilder
    STRIPPED_KEYS = %w[DOKKU_PROXY_PORT DOKKU_PROXY_SSL_PORT].freeze

    def initialize(parent_app)
      @parent_app = parent_app
    end

    def build
      result = {}
      apply!(result, scope: "production")
      apply!(result, scope: "both")
      apply!(result, scope: "preview")
      STRIPPED_KEYS.each { |k| result.delete(k) }
      result
    end

    private

    def apply!(result, scope:)
      @parent_app.env_vars.where(scope: scope).find_each do |ev|
        result[ev.key] = ev.value
      end
    end
  end
end
