module Hosts
  # Maps a host container name back to its app. Dokku-era containers are
  # <app>.<proc>.<n>; wokkud Swarm tasks are wokku-<app>-<proc>.<slot>.<task>.
  # App names may contain '-', so the longest app name that prefixes the
  # service wins. One-off run containers (wokku-run-<app>-<op>) map to nothing.
  # ponytail: name parsing; switch to the wokku.app label if callers ever read the Docker API.
  module ContainerNames
    def self.app_for(container_name, apps_by_name)
      base = container_name.to_s.split(".").first.to_s
      return apps_by_name[base] if apps_by_name.key?(base)
      return unless base.start_with?("wokku-") && !base.start_with?("wokku-run-")

      rest = base.delete_prefix("wokku-")
      name = apps_by_name.keys.select { |n| rest.start_with?("#{n}-") }.max_by(&:length)
      apps_by_name[name] if name
    end
  end
end
