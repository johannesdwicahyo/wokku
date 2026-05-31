module Molecules
  class KvSummaryCardComponent < ApplicationComponent
    def initialize(app:)
      @app = app
      @kv  = app.respond_to?(:primary_redis) ? app.primary_redis : nil
    end
    attr_reader :app, :kv

    def usage_mb; kv&.size_mb_used.to_i; end
    def max_mb;   kv&.size_mb_max.to_i; end
    def pct;      max_mb.positive? ? (usage_mb * 100.0 / max_mb).round(1) : 0; end
  end
end
