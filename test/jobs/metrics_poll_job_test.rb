require "test_helper"

class MetricsPollJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      MetricsPollJob.perform_later(@server.id)
    end
  end

  test "creates metric records for known apps" do
    app = app_records(:one)
    container_name = "#{app.name}.web.1"

    docker_stats_line = {
      "Name" => container_name,
      "CPUPerc" => "5.20%",
      "MemUsage" => "128MiB / 512MiB",
      "NetIO" => "1kB / 2kB",
      "BlockIO" => "0B / 0B",
      "MemPerc" => "25.00%",
      "PIDs" => "5"
    }.to_json

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| docker_stats_line }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    assert_difference "Metric.count", 1 do
      MetricsPollJob.perform_now(@server.id)
    end

    metric = Metric.last
    assert_in_delta 5.2, metric.cpu_percent, 0.01
    assert_equal 128 * 1024 * 1024, metric.memory_usage
    assert_equal 512 * 1024 * 1024, metric.memory_limit
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "logs warning but does not raise on SSH failure" do
    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &_block| raise Net::SSH::Exception, "connection refused" }
    end

    assert_nothing_raised do
      MetricsPollJob.perform_now(@server.id)
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "skips containers not matching known apps" do
    unknown_stats_line = {
      "Name" => "unknown-container.web.1",
      "CPUPerc" => "1.00%",
      "MemUsage" => "64MiB / 512MiB",
      "NetIO" => "0B / 0B",
      "BlockIO" => "0B / 0B",
      "MemPerc" => "12.50%",
      "PIDs" => "2"
    }.to_json

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| unknown_stats_line }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    assert_no_difference "Metric.count" do
      MetricsPollJob.perform_now(@server.id)
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "handles empty docker stats output gracefully" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| "" }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    assert_nothing_raised do
      assert_no_difference "Metric.count" do
        MetricsPollJob.perform_now(@server.id)
      end
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "handles JSON parse error gracefully" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| "not valid json\n" }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    assert_nothing_raised do
      MetricsPollJob.perform_now(@server.id)
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "parse_bytes handles GiB unit" do
    job = MetricsPollJob.new
    assert_equal (2 * 1024 * 1024 * 1024).to_i, job.send(:parse_bytes, "2GiB")
  end

  test "parse_bytes handles MiB unit" do
    job = MetricsPollJob.new
    assert_equal (128 * 1024 * 1024).to_i, job.send(:parse_bytes, "128MiB")
  end

  test "parse_bytes handles KiB unit" do
    job = MetricsPollJob.new
    assert_equal (256 * 1024).to_i, job.send(:parse_bytes, "256KiB")
  end

  test "parse_bytes handles raw bytes" do
    job = MetricsPollJob.new
    assert_equal 1024, job.send(:parse_bytes, "1024")
  end

  test "creates multiple metrics for multiple matching containers" do
    app = app_records(:one)

    lines = [
      { "Name" => "#{app.name}.web.1", "CPUPerc" => "1.00%", "MemUsage" => "64MiB / 256MiB",
        "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "25.00%", "PIDs" => "1" }.to_json,
      { "Name" => "#{app.name}.worker.1", "CPUPerc" => "2.00%", "MemUsage" => "32MiB / 256MiB",
        "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "12.50%", "PIDs" => "1" }.to_json
    ].join("\n")

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| lines }

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    assert_difference "Metric.count", 2 do
      MetricsPollJob.perform_now(@server.id)
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "does not raise on ECONNREFUSED" do
    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &_block| raise Errno::ECONNREFUSED }
    end

    assert_nothing_raised do
      MetricsPollJob.perform_now(@server.id)
    end
  ensure
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end
end
