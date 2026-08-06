module Apps
  # B6 W4: every app runs as Swarm services — logs read from
  # `docker service logs`. Reads go over the same root SSH wokkud uses for
  # host ops (Hosts::Ssh since W7 Phase 2).
  class LogReader
    def self.recent(app, lines: 100)
      name = Shellwords.escape(app.name)
      out = Hosts::Ssh.new(app.server).run_raw(
        "for s in $(docker service ls --filter label=wokku.app=#{name} --format '{{.Name}}'); do " \
        "docker service logs --tail #{lines.to_i} --timestamps $s 2>&1; done | sort | tail -n #{lines.to_i}"
      )
      return "No running services for this app — deploy first." if out.blank?
      out
    end

    # Streaming follow of the web service only (the one users watch during
    # deploys).
    def self.tail(app, &block)
      Hosts::Ssh.new(app.server).run_raw_streaming(
        "docker service logs --follow --tail 50 --timestamps #{Shellwords.escape("wokku-#{app.name}-web")}", &block
      )
    end
  end
end
