# The engine's config/routes.rb auto-draws (non-isolated). A HOST must
# define its own root — the engine deliberately doesn't (the cloud host's
# root is its marketing landing; a self-host's root is the dashboard).
Rails.application.routes.draw do
  root to: redirect("/dashboard/apps")
end
