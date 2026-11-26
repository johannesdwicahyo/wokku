module Apps
  # Every number on the app detail screen in 4 fixed queries: 24 hourly
  # cpu/mem/req values (oldest first, nil = no data) plus last-hour readouts.
  class DetailStats
    HOURS = 24
    MB = 1024 * 1024.0

    def self.for(app, now: Time.current) = new(app, now).call

    def initialize(app, now)
      @app = app
      @now = now.utc
    end

    def call
      start = @now.beginning_of_hour - (HOURS - 1).hours
      cpu, mem, limit = metric_series(start)
      last = Metric.where(app_record_id: @app.id).order(recorded_at: :desc).pick(:cpu_percent, :memory_usage, :memory_limit)
      req, rpm_now, p95, hour_reqs, hour_5xx = request_stats(start)
      mem_now = @app.live_mem_used_mb || (last && last[1] && (last[1] / MB).round)
      lim = limit || (last && last[2] && last[2] / MB)
      {
        cpu: cpu, mem: mem, req: req,
        cpu_now: last&.first&.to_f,
        mem_now_mb: mem_now&.to_i,
        mem_limit_mb: lim&.round,
        rpm_now: rpm_now,
        p95_ms: p95,
        req_hour: hour_reqs,
        err_5xx_hour: hour_5xx,
        err_5xx_pct: hour_reqs.zero? ? nil : (hour_5xx * 100.0 / hour_reqs).round(2)
      }
    end

    private

    def slot(time, start) = ((time.to_i - start.to_i) / 3600)

    # Raw rows win; MetricHourly fills hours the rollup already compacted.
    def metric_series(start)
      cpu = Array.new(HOURS)
      mem = Array.new(HOURS)
      limit = nil
      hourly = MetricHourly.for_app(@app).since(start)
                           .pluck(:hour_start, :avg_cpu_percent, :avg_memory_usage, :memory_limit)
      hourly.each do |h, c, m, l|
        i = slot(h, start)
        next unless (0...HOURS).cover?(i)
        cpu[i] = c&.to_f
        mem[i] = m && (m / MB).round(1)
        limit = l / MB if l
      end
      hour = "DATE_TRUNC('hour', recorded_at)"
      Metric.where(app_record_id: @app.id, recorded_at: start..@now).group(Arel.sql(hour))
            .pluck(Arel.sql(hour), Arel.sql("AVG(cpu_percent)"), Arel.sql("AVG(memory_usage)"), Arel.sql("MAX(memory_limit)"))
            .each do |h, c, m, l|
        i = slot(h, start)
        next unless (0...HOURS).cover?(i)
        cpu[i] = c&.to_f
        mem[i] = m && (m.to_f / MB).round(1)
        limit = l / MB if l
      end
      [ cpu, mem, limit ]
    end

    # One query of 5-minute buckets (<= 288 rows), folded in Ruby.
    def request_stats(start)
      req = Array.new(HOURS)
      hour_ago = @now - 1.hour
      hour_reqs = hour_5xx = 0
      p95 = nil
      sums = Hash.new(0)
      RequestAggregate.for_app(@app).since(start)
                      .pluck(:bucket_start, :req_count, :error_5xx, :p95_ms).each do |t, n, e, p|
        i = slot(t, start)
        sums[i] += n if (0...HOURS).cover?(i)
        next unless t >= hour_ago && t <= @now
        hour_reqs += n
        hour_5xx += e
        p95 = [ p95, p ].compact.max if p
      end
      sums.each { |i, n| req[i] = (n / 60.0).round(1) }
      [ req, hour_reqs.positive? ? (hour_reqs / 60.0).round(1) : nil, p95, hour_reqs, hour_5xx ]
    end
  end
end
