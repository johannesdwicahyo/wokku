module Wokku
  # The Wokku core engine. Carries the open-source product surface
  # (models, controllers, UI, jobs, services). NOT isolate_namespace'd:
  # the engine's classes live in the same top-level namespace as the host
  # app so existing constants (AppRecord, Dashboard::*, etc.) keep working
  # unchanged as they migrate in. See the OSS/managed split design doc.
  class Engine < ::Rails::Engine
    # Fresh OSS installs migrate from the engine's db/migrate (the
    # baseline no-ops wherever the schema already exists).
    initializer "wokku.migrations" do |app|
      app.config.paths["db/migrate"] << root.join("db/migrate").to_s
    end

    initializer "wokku.assets" do |app|
      app.config.assets.paths << root.join("app/javascript") if app.config.respond_to?(:assets)
    end

    initializer "wokku.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb") if app.config.respond_to?(:importmap)
    end

    # Engine views must beat GEM views (Devise's bundled devise/* templates
    # were shadowing the engine's custom ones — gem railtie order decides
    # otherwise). Host app/views and engine app/views are disjoint sets
    # (files moved, never duplicated), so prepending cannot shadow the host.
    initializer "wokku.view_paths" do
      config.to_prepare do
        # Guard: to_prepare re-runs on every dev reload and prepend_view_path
        # stacks — skip when the engine path is already first.
        path = Wokku::Engine.root.join("app/views").to_s
        [ ApplicationController, ApplicationMailer ].each do |klass|
          klass.prepend_view_path(path) unless klass.view_paths.paths.first&.to_s == path
        end
      end
    end
  end
end
