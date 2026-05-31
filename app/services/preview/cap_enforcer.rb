module Preview
  class CapEnforcer
    CAP = 3

    def self.allow?(team)
      count(team) < CAP
    end

    def self.count(team)
      AppRecord.previews.where(team: team).count
    end

    def self.cap
      CAP
    end
  end
end
