module Hosts
  # THE single home for interpreting host command failures. Controllers must
  # not match on error strings anywhere else — add new patterns here so
  # every surface (API, dashboard, jobs) classifies identically.
  # The returned codes (dokku_command_failed etc.) are API client contract —
  # do NOT rename them.
  class ErrorClassifier
    RULES = [
      [ /unable to remove deploy lock|deploy lock in place|another deploy is in progress|currently being deployed/i, :deploy_lock_held ],
      [ /no such container|has not been deployed/i,                :app_not_running ],
      [ /is not a dokku command|plugin .* does not exist/i,        :plugin_missing ],
      [ /already exists/i,                                         :already_exists ],
      [ /app locked/i,                                             :app_locked ],
      [ /not found|does not exist/i,                               :not_found_on_host ]
    ].freeze

    def self.classify(exception)
      return :host_unreachable if exception.is_a?(Hosts::Ssh::ConnectionError) # TimeoutError < ConnectionError

      msg = exception.message.to_s
      RULES.each { |pattern, code| return code if msg.match?(pattern) }
      :dokku_command_failed
    end
  end
end
