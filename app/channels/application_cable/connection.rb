module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user_from_bearer_token || user_from_warden || reject_unauthorized_connection
    end

    def user_from_bearer_token
      header = env["HTTP_AUTHORIZATION"]
      return nil if header.blank?

      plain_token = header.match(/^Bearer\s+(.+)$/)&.captures&.first
      return nil if plain_token.blank?

      token = ApiToken.find_by_token(plain_token)
      # Read tokens never get a socket: the terminal channel runs commands.
      return nil if token.nil? || !token.active? || token.read_only? || token.user.abuse_suspended?

      token.touch_last_used!
      token.user
    end

    def user_from_warden
      env["warden"]&.user
    end
  end
end
