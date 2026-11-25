module Apps
  # CPU % per app over the last hour in 5-minute buckets (oldest first), from
  # Metric rows in one grouped query. Per poll we sum the app's containers,
  # then average the polls inside a bucket; empty buckets are nil.
  class CpuSparks
    BUCKET = 5.minutes

    def self.for(apps, now: Time.current, buckets: 12)
      since = now - (BUCKET * buckets)
      idx = "FLOOR(EXTRACT(EPOCH FROM (#{Metric.connection.quote(now.utc)}::timestamp - recorded_at)) / #{BUCKET.to_i})::int"
      polls = Metric.where(app_record_id: apps.map(&:id), recorded_at: since..now)
                    .group(:app_record_id, :recorded_at, Arel.sql(idx))
                    .pluck(:app_record_id, Arel.sql(idx), Arel.sql("SUM(cpu_percent)"))
      per = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
      polls.each { |app_id, age, sum| per[app_id][age] << sum.to_f }
      apps.to_h do |app|
        series = Array.new(buckets) do |i|
          vals = per[app.id][buckets - 1 - i]
          vals.empty? ? nil : (vals.sum / vals.size).round
        end
        [ app.id, series ]
      end
    end
  end
end
