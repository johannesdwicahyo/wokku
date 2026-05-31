require "rails_helper"
require "rake"

RSpec.describe "vector:install — requests sink" do
  before(:all) do
    Rake.application.load_rakefile unless Rake::Task.task_defined?("vector:install")
  end

  describe "#vector_config_yaml second sink" do
    let(:task) { Rake::Task["vector:show_config"] }

    it "embeds a second http sink pointing at /api/v1/requests/ingest" do
      yaml = capture_stdout { task.reenable; task.invoke("https://wokku.cloud/api/v1/logs/ingest") }
      expect(yaml).to include("wokku_requests:")
      expect(yaml).to include("uri: https://wokku.cloud/api/v1/requests/ingest")
    end

    it "includes the parse_nginx_requests remap transform with nginx-proxy filter" do
      yaml = capture_stdout { task.reenable; task.invoke }
      expect(yaml).to include("parse_nginx_requests:")
      expect(yaml).to include('container_name != "nginx-proxy"')
      expect(yaml).to include("parse_regex")
    end

    it "honors an explicit requests_url override" do
      yaml = capture_stdout { task.reenable; task.invoke("https://wokku.cloud/api/v1/logs/ingest", "https://staging.example/api/v1/requests/ingest") }
      expect(yaml).to include("uri: https://staging.example/api/v1/requests/ingest")
    end

    it "reuses the same bearer token env var for the requests sink" do
      yaml = capture_stdout { task.reenable; task.invoke }
      # Both sinks reference ${WOKKU_INGEST_TOKEN} — count should be >= 2
      expect(yaml.scan("${WOKKU_INGEST_TOKEN}").size).to be >= 2
    end
  end

  def capture_stdout
    old, $stdout = $stdout, StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
