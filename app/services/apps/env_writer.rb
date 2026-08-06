module Apps
  # The single write path for app env vars (B6 W2/W3): EnvVar rows are the
  # control-plane truth for every app. The dokku config mirror died with the
  # cp-env-truth flip (W7 Phase 1 dead-branch collapse).
  class EnvWriter
    def self.set(app, vars)
      vars.each do |key, value|
        row = app.env_vars.find_or_initialize_by(key: key.to_s)
        row.value = value.to_s
        row.save!
      end
    end

    def self.unset(app, *keys)
      app.env_vars.where(key: keys.map(&:to_s)).destroy_all
    end
  end
end
