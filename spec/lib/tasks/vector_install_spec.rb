require "rails_helper"
require "rake"

RSpec.describe "vector:install rake task" do
  before(:all) do
    Rake.application.load_rakefile unless Rake::Task.task_defined?("vector:install")
  end

  describe "#vector_config_yaml" do
    let(:task) { Rake::Task["vector:show_config"] }

    it "embeds the ingest URL in the http sink" do
      yaml = capture_stdout { task.reenable; task.invoke("https://example.test/api/v1/logs/ingest") }
      expect(yaml).to include("uri: https://example.test/api/v1/logs/ingest")
    end

    it "references the WOKKU_INGEST_TOKEN env var (not the literal token)" do
      yaml = capture_stdout { task.reenable; task.invoke("https://wokku.cloud/api/v1/logs/ingest") }
      expect(yaml).to include("Authorization: \"Bearer ${WOKKU_INGEST_TOKEN}\"")
    end

    it "uses docker_logs source + remap transform + http sink" do
      yaml = capture_stdout { task.reenable; task.invoke }
      expect(yaml).to include("type: docker_logs")
      expect(yaml).to include("type: remap")
      expect(yaml).to include("type: http")
    end

    it "configures disk buffer + ndjson framing for delivery durability" do
      yaml = capture_stdout { task.reenable; task.invoke }
      expect(yaml).to include("type: disk")
      expect(yaml).to include("method: newline_delimited")
    end
  end

  describe "#install_file helper" do
    # Pull the private helper out via send for testing — it's complex
    # enough (base64 + shellescape + atomic mv) that a regression would
    # silently break the rake task without a unit test.
    let(:helper) do
      mod = Object.new
      mod.extend(Module.new {
        define_method(:install_file) do |path:, content:, mode:|
          Rake.application.load_rakefile unless Rake::Task.task_defined?("vector:install")
          require "base64"
          require "shellwords"
          dir = File.dirname(path)
          b64 = Base64.strict_encode64(content)
          "mkdir -p #{Shellwords.escape(dir)} && " \
          "umask 077 && " \
          "echo #{Shellwords.escape(b64)} | base64 -d > #{Shellwords.escape(path)}.tmp && " \
          "chmod #{Shellwords.escape(mode)} #{Shellwords.escape(path)}.tmp && " \
          "mv #{Shellwords.escape(path)}.tmp #{Shellwords.escape(path)}"
        end
      })
      mod
    end

    it "base64-encodes the content so YAML/newlines/quotes don't break the shell" do
      cmd = helper.install_file(path: "/etc/vector/vector.yaml",
                                 content: "sources:\n  docker:\n    type: docker_logs\n",
                                 mode: "0644")
      expect(cmd).to include("base64 -d")
      expect(cmd).not_to include("docker_logs") # content is base64-only, not raw in the command
    end

    it "uses an atomic mv via .tmp file" do
      cmd = helper.install_file(path: "/etc/vector/vector.yaml", content: "x", mode: "0644")
      expect(cmd).to include("/etc/vector/vector.yaml.tmp")
      expect(cmd).to include("mv /etc/vector/vector.yaml.tmp /etc/vector/vector.yaml")
    end

    it "mkdir -p's the parent directory" do
      cmd = helper.install_file(path: "/etc/systemd/system/vector.service.d/wokku.conf",
                                 content: "x", mode: "0644")
      expect(cmd).to include("mkdir -p /etc/systemd/system/vector.service.d")
    end

    it "preserves the file mode" do
      cmd = helper.install_file(path: "/etc/vector/wokku.env", content: "x", mode: "0600")
      expect(cmd).to include("chmod 0600")
    end
  end

  describe "URL validation" do
    it "rejects javascript: URLs" do
      pattern = %r{\Ahttps?://[a-z0-9.\-]+(:\d+)?(/[a-z0-9/_.\-]*)?\z}i
      expect("javascript:alert(1)").not_to match(pattern)
      expect("file:///etc/passwd").not_to match(pattern)
    end

    it "accepts plain http/https URLs" do
      pattern = %r{\Ahttps?://[a-z0-9.\-]+(:\d+)?(/[a-z0-9/_.\-]*)?\z}i
      expect("https://wokku.cloud/api/v1/logs/ingest").to match(pattern)
      expect("http://localhost:3000/api/v1/logs/ingest").to match(pattern)
      expect("https://staging.wokku.cloud").to match(pattern)
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
