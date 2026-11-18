# Singleton row of install-wide settings (admin → settings).
class SiteSetting < ApplicationRecord
  def self.current = first || create!

  # Read path for layouts: no row is created just by rendering a page.
  def self.body_scripts = first&.body_scripts
end
