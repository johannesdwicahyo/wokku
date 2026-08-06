module Apps
  module DevSession
    class Revoker
      def initialize(session)
        @session = session
      end

      def call!
        return true if @session.revoked_at.present?
        Apps::DevSession::AuthorizedKeysWriter.new(@session.app_record).remove(ssh_principal: @session.ssh_principal)
        @session.update!(revoked_at: Time.current)
        true
      end
    end
  end
end
