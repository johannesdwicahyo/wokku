class EnsureLiveAppSegments < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(Billing::EnsureLiveAppSegments)
    stats = Billing::EnsureLiveAppSegments.call
    say "EnsureLiveAppSegments: #{stats.inspect}"
  end

  def down
    # Idempotent forward-only recovery; closing segments is the wrong
    # inverse because we can't tell which were created here vs. in the
    # normal allocation flow.
  end
end
