module AppJson
  # Validates an app's currently-set Dokku env vars against the schema
  # declared in its on-host `app.json`. Heroku-compatible env block
  # shape:
  #
  #   "env": {
  #     "DATABASE_URL":    { "required": true, "description": "..." },
  #     "SECRET_KEY_BASE": { "required": true, "generator": "secret" },
  #     "PORT":            { "value": "3000" },
  #     "FEATURE_FLAG":    { "required": false, "description": "..." }
  #   }
  #
  # A var is *required* when `required` is truthy AND no `value` /
  # `generator` default is declared (those auto-populate, so they're
  # not really required from the user's perspective). All other entries
  # are *recommended* — the deploy still goes ahead but we tell the
  # user about them.
  #
  # Returns a Result struct with separate required/recommended lists +
  # the keys actually set. Lean enough to render in a dashboard panel
  # without further processing.
  class EnvValidator
    Result = Struct.new(:required, :recommended, :missing_required,
                        :missing_recommended, :set_keys, keyword_init: true) do
      def valid?           ; missing_required.empty? ; end
      def has_warnings?    ; missing_recommended.any? ; end
      def total_required   ; required.size ; end
      def required_set     ; required.size - missing_required.size ; end
    end

    EMPTY = Result.new(required: [], recommended: [], missing_required: [],
                       missing_recommended: [], set_keys: []).freeze

    def self.call(app_json:, env_keys:)
      new(app_json: app_json, env_keys: env_keys).call
    end

    def initialize(app_json:, env_keys:)
      @app_json = app_json || {}
      @env_keys = (env_keys || []).map(&:to_s).to_set
    end

    def call
      env_block = @app_json["env"]
      return EMPTY unless env_block.is_a?(Hash) && env_block.any?

      required    = []
      recommended = []

      env_block.each do |key, spec|
        spec ||= {}
        # `value` and `generator` mean "Dokku auto-populates this", so
        # the user isn't actually expected to set it. We surface them
        # as recommended only if `required: true` AND no auto-source.
        has_auto_source = spec.is_a?(Hash) && (spec["value"].present? || spec["generator"].present?)
        is_required     = spec.is_a?(Hash) && spec["required"]

        entry = build_entry(key, spec)
        if is_required && !has_auto_source
          required << entry
        else
          recommended << entry
        end
      end

      Result.new(
        required:           required,
        recommended:        recommended,
        missing_required:   required.reject    { |e| @env_keys.include?(e[:key]) },
        missing_recommended: recommended.reject { |e| @env_keys.include?(e[:key]) },
        set_keys:           @env_keys.to_a
      )
    end

    private

    def build_entry(key, spec)
      {
        key:         key,
        description: spec.is_a?(Hash) ? spec["description"].to_s.strip.presence : nil,
        generator:   spec.is_a?(Hash) ? spec["generator"].to_s.strip.presence   : nil,
        value:       spec.is_a?(Hash) ? spec["value"]                            : nil
      }
    end
  end
end
