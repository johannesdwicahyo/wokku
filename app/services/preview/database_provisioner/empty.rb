module Preview
  module DatabaseProvisioner
    class Empty
      def initialize(preview_app)
        @preview_app = preview_app
        @parent      = preview_app.parent_app
      end

      def provision
        return if @parent.nil?

        client = Dokku::Client.new(@preview_app.server)
        dbs    = Dokku::Databases.new(client)

        @parent.database_services.find_each do |svc|
          preview_db_name = derive_preview_db_name(svc.name)
          dbs.create(svc.service_type, preview_db_name)
          dbs.link(svc.service_type, preview_db_name, @preview_app.preview_subdomain)
        end
      end

      private

      # Replace the parent app's name prefix in the DB name with the
      # preview's subdomain. Works for the common Dokku convention where
      # databases are named `<app>-<role>` (e.g. myapp-db, myapp-cache).
      # Falls back to appending `-db` if the parent prefix doesn't match.
      def derive_preview_db_name(parent_db_name)
        prefix  = "#{@parent.name}-"
        suffix  = parent_db_name.start_with?(prefix) ? parent_db_name.sub(prefix, "") : "db"
        "#{@preview_app.preview_subdomain}-#{suffix}"
      end
    end
  end
end
