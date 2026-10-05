namespace :wokku do
  namespace :shared do
    desc "Ensure the shared datastore parent (default: mariadb) on every wokkud server — pre-warm after deploy"
    task :ensure_parents, [ :engine ] => :environment do |_, args|
      engine = (args[:engine].presence || "mariadb").to_s
      Server.where(wokkud_services_enabled: true).find_each do |server|
        parent = DatabaseProvisioner.ensure_shared_parent!(server: server, engine: engine)
        puts "#{server.name}: #{parent ? "#{parent.name} ensured" : "skipped (no #{engine} parent)"}"
      rescue StandardError => e
        puts "#{server.name}: FAILED #{e.class}: #{e.message}"
      end
    end
  end
end
