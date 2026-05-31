module Dokku
  module Passthrough
    module Denylist
      BLOCKED_VERBS = %w[
        plugin:install plugin:uninstall plugin:update
        ssh-keys:add ssh-keys:remove
        acl:add acl:remove
        scheduler:set
        git:auth git:auth-unset
      ].freeze

      def self.allow?(verb, user, force: false)
        return false if verb.blank?
        return true if user&.admin? && force
        !BLOCKED_VERBS.include?(verb.to_s)
      end
    end
  end
end
