# One row of install-wide settings the admin edits in admin → settings.
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings, id: :uuid do |t|
      # Raw HTML injected before </body> on dashboard + docs pages.
      t.text :body_scripts
      t.timestamps
    end
  end
end
