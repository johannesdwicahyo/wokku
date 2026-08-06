module Apps
  # Restart an app by rotating its Swarm services via stack.converge
  # (restart:true forces the update).
  class Restarter
    def self.restart(app)
      # ::-prefixed — Apps::Lifecycle (cluster-B services) shadows the
      # top-level Lifecycle module from inside this namespace.
      ::Lifecycle::Ops.converge!(app, restart: true)
    end
  end
end
