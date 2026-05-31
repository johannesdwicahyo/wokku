# Mount the maintenance gate AFTER Warden so we can read the signed-in
# user from the session and let admins through. Devise injects Warden via
# its Rails engine; inserting after Warden::Manager is the canonical hook.
require Rails.root.join("app/middleware/maintenance_gate")

Rails.application.config.middleware.insert_after Warden::Manager, MaintenanceGate
