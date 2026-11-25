module Apps
  # Fleet board data: one light per process instance, grouped by app.
  # Reads only the preloaded dyno_allocations (no queries).
  class Fleet
    STATES = %i[running deploying sleeping crashed stopped created].freeze

    def self.for(apps)
      apps.map do |app|
        n = app.dyno_allocations.sum(&:count)
        state = STATES.include?(app.status&.to_sym) ? app.status.to_sym : :created
        { app_id: app.id, name: app.name, states: Array.new([ n, 1 ].max, state) }
      end
    end

    def self.counts(fleet)
      fleet.flat_map { |a| a[:states] }.tally
    end
  end
end
