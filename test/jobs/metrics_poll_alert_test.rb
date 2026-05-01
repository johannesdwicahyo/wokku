require "test_helper"

class MetricsPollAlertTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @app = app_records(:one)
    # Use memory_store so cache operations actually persist during tests
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  # Helper to run the job with given CPUPerc and MemUsage stats
  def run_job_with_stats(cpu_perc:, mem_usage:)
    container_name = "#{@app.name}.web.1"
    line = {
      "Name" => container_name,
      "CPUPerc" => cpu_perc,
      "MemUsage" => mem_usage,
      "NetIO" => "0B / 0B",
      "BlockIO" => "0B / 0B",
      "MemPerc" => "0%",
      "PIDs" => "1"
    }.to_json

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| line }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    MetricsPollJob.perform_now(@server.id)
  end

  # --- CPU threshold tests ---

  test "does not fire alert on first high CPU reading" do
    assert_no_enqueued_jobs only: NotifyJob do
      run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    end
  end

  test "increments CPU cache counter to 1 on first high reading" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_cpu"
    assert_equal 1, Rails.cache.read(cache_key), "Cache counter should be 1 after first high reading"
  end

  test "resets CPU counter when reading drops below threshold" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    run_job_with_stats(cpu_perc: "50.0%", mem_usage: "128MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_cpu"
    assert_nil Rails.cache.read(cache_key), "Cache key should be deleted after low CPU reading"
  end

  test "resets CPU counter to 0 after alert fires on second consecutive high reading" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_cpu"
    assert_equal 0, Rails.cache.read(cache_key), "Cache counter should reset to 0 after alert fires"
  end

  test "does not increment CPU counter when CPU is at exactly the threshold" do
    run_job_with_stats(cpu_perc: "80.0%", mem_usage: "128MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_cpu"
    assert_nil Rails.cache.read(cache_key), "Cache key should not exist at exactly threshold"
  end

  # --- Memory threshold tests ---

  test "does not fire alert on first high memory reading" do
    assert_no_enqueued_jobs only: NotifyJob do
      # ~92% memory: 471MiB / 512MiB
      run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    end
  end

  test "increments memory cache counter to 1 on first high reading" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_memory"
    assert_equal 1, Rails.cache.read(cache_key), "Memory counter should be 1 after first high reading"
  end

  test "resets memory counter when usage drops below threshold" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "128MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_memory"
    assert_nil Rails.cache.read(cache_key), "Memory cache key should be deleted after low reading"
  end

  test "resets memory counter to 0 after alert fires on second consecutive high reading" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")

    cache_key = "alert:#{@app.id}:resource_high_memory"
    assert_equal 0, Rails.cache.read(cache_key), "Memory counter should reset to 0 after alert fires"
  end

  # --- check_threshold unit tests (direct method calls) ---

  test "check_threshold increments cache on first breach" do
    job = MetricsPollJob.new
    job.send(:check_threshold, @app, "resource_high_cpu", 85.0, 80.0)

    assert_equal 1, Rails.cache.read("alert:#{@app.id}:resource_high_cpu")
  end

  test "check_threshold deletes cache key when value is below threshold" do
    Rails.cache.write("alert:#{@app.id}:resource_high_cpu", 1, expires_in: 1.hour)

    job = MetricsPollJob.new
    job.send(:check_threshold, @app, "resource_high_cpu", 50.0, 80.0)

    assert_nil Rails.cache.read("alert:#{@app.id}:resource_high_cpu")
  end

  test "check_threshold does not trigger at exactly threshold value" do
    job = MetricsPollJob.new
    job.send(:check_threshold, @app, "resource_high_cpu", 80.0, 80.0)

    assert_nil Rails.cache.read("alert:#{@app.id}:resource_high_cpu")
  end

  test "check_threshold resets counter to 0 after firing alert on second breach" do
    job = MetricsPollJob.new
    job.send(:check_threshold, @app, "resource_high_cpu", 85.0, 80.0)
    job.send(:check_threshold, @app, "resource_high_cpu", 85.0, 80.0)

    assert_equal 0, Rails.cache.read("alert:#{@app.id}:resource_high_cpu"),
      "Counter should be reset to 0 after alert fires"
  end
end
