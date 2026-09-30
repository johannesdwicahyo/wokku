class UpgradeError < StandardError
  ENGINE_LABEL = { "postgres" => "Postgres", "redis" => "Redis" }.freeze

  def self.engine_label(engine)
    ENGINE_LABEL[engine.to_s] || engine.to_s.capitalize
  end

  class NoSharedTenant < UpgradeError
    UI_MESSAGE = "No shared %{engine} found on this app.".freeze
    def initialize(engine: "postgres")
      super(format(UI_MESSAGE, engine: UpgradeError.engine_label(engine)))
    end
  end

  class PlanNoSlots < UpgradeError
    UI_MESSAGE = "Your plan doesn't include dedicated %{engine}. Upgrade to Solo or higher.".freeze
    def initialize(engine: "postgres")
      super(format(UI_MESSAGE, engine: UpgradeError.engine_label(engine)))
    end
  end

  class NoFreeSlots < UpgradeError
    UI_MESSAGE = "You're using all your dedicated %{engine} slots. Drop one to upgrade another.".freeze
    def initialize(engine: "postgres")
      super(format(UI_MESSAGE, engine: UpgradeError.engine_label(engine)))
    end
  end

  class ExceedsDedicatedCap < UpgradeError
    def initialize(size_mb:, cap_mb:, plan:, next_plan:, engine: "postgres")
      label = UpgradeError.engine_label(engine)
      super("Your #{label} is #{size_mb} MB but #{plan}'s dedicated cap is #{cap_mb} MB. Upgrade to #{next_plan} to migrate.")
    end
    UI_MESSAGE = "Your dataset exceeds the dedicated size cap for your plan.".freeze
  end

  # Builder mode: the plan enforcer / capacity guard refused the shape.
  # Raised with Resources::ApplyChange's message.
  class OverLimit < UpgradeError
    UI_MESSAGE = "That size is over your account limit — pay your first invoice to go higher.".freeze
    def initialize(msg = UI_MESSAGE); super; end
  end

  class ProvisioningFailed < UpgradeError
    UI_MESSAGE = "We couldn't provision a dedicated container. Try again or contact support.".freeze
    def initialize(msg = UI_MESSAGE); super; end
  end

  class MigrationFailed < UpgradeError
    UI_MESSAGE = "Data migration failed. Your app is still on the shared store.".freeze
    def initialize(msg = UI_MESSAGE); super; end
  end

  class CutoverFailed < UpgradeError
    UI_MESSAGE = "Upgrade reverted — your app is back on the shared store.".freeze
    def initialize(msg = UI_MESSAGE); super; end
  end

  class RollbackFailed < UpgradeError
    UI_MESSAGE = "Upgrade and rollback both failed. We've alerted the team.".freeze
    def initialize(msg = UI_MESSAGE); super; end
  end
end
