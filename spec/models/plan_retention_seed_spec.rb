require "rails_helper"

# Sanity-check that every plan ships with sane retention defaults so
# the per-plan retention jobs can't divide-by-zero or accidentally
# delete the entire table for a misconfigured plan.
RSpec.describe Plan, "retention defaults" do
  let(:plans) { Plan.where(key: Plan::KEYS) }

  it "every seeded plan has positive retention windows" do
    plans.find_each do |p|
      expect(p.log_retention_days).to              be > 0, "#{p.key} log_retention_days"
      expect(p.sample_retention_hours).to          be > 0, "#{p.key} sample_retention_hours"
      expect(p.metric_high_res_days).to            be > 0, "#{p.key} metric_high_res_days"
      expect(p.metric_aggregate_retention_days).to be > 0, "#{p.key} metric_aggregate_retention_days"
    end
  end

  it "retention scales up monotonically Free → Solo → Pro → Team" do
    ordered = Plan::KEYS.map { |k| Plan.find_by!(key: k) }
    %i[log_retention_days sample_retention_hours metric_high_res_days metric_aggregate_retention_days].each do |col|
      vals = ordered.map(&col)
      expect(vals).to eq(vals.sort), "#{col} should be monotonic: got #{vals.inspect}"
    end
  end
end
