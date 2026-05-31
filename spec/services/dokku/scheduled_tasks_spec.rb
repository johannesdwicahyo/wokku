require "rails_helper"

RSpec.describe Dokku::ScheduledTasks do
  let(:app)    { create(:app_record) }
  let(:client) { instance_double(Dokku::Client) }

  describe "#sync!" do
    it "writes enabled tasks to app.json cron + triggers rebuild" do
      create(:scheduled_task, app_record: app, command: "echo nightly", schedule: "0 3 * * *", enabled: true)
      create(:scheduled_task, app_record: app, command: "echo skip",    schedule: "0 4 * * *", enabled: false)

      # Reads existing app.json (returns empty object)
      expect(client).to receive(:run)
        .with(/^cat .*app\.json/, timeout: 15)
        .and_return("{}")

      # Writes the patched app.json via stdin
      written_json = nil
      expect(client).to receive(:run) do |cmd, **opts|
        if cmd.start_with?("cat > ")
          written_json = opts[:stdin]
        end
      end

      # Triggers rebuild (only when there are enabled tasks)
      expect(client).to receive(:run).with(/ps:rebuild /, timeout: anything)

      result = described_class.new(app, client: client).sync!

      expect(result.success?).to be true
      expect(result.task_count).to eq(1)
      parsed = JSON.parse(written_json)
      expect(parsed["cron"]).to eq([ { "command" => "echo nightly", "schedule" => "0 3 * * *" } ])
    end

    it "writes an empty cron array when no enabled tasks exist (and does not rebuild)" do
      create(:scheduled_task, app_record: app, enabled: false)

      expect(client).to receive(:run).with(/^cat .*app\.json/, timeout: 15).and_return("{}")
      expect(client).to receive(:run).with(/^cat > /, anything).and_return(nil)
      expect(client).not_to receive(:run).with(/ps:rebuild/, anything)

      result = described_class.new(app, client: client).sync!
      expect(result.success?).to be true
      expect(result.task_count).to eq(0)
    end

    it "preserves other keys in app.json when patching" do
      create(:scheduled_task, app_record: app, command: "echo hi", schedule: "0 5 * * *")

      existing = { "scripts" => { "dokku" => { "predeploy" => "echo deploy" } } }.to_json
      expect(client).to receive(:run).with(/^cat .*app\.json/, timeout: 15).and_return(existing)

      written_json = nil
      expect(client).to receive(:run) do |cmd, **opts|
        if cmd.start_with?("cat > ")
          written_json = opts[:stdin]
        end
      end
      expect(client).to receive(:run).with(/ps:rebuild/, timeout: anything)

      described_class.new(app, client: client).sync!

      parsed = JSON.parse(written_json)
      expect(parsed["scripts"]).to eq({ "dokku" => { "predeploy" => "echo deploy" } })
      expect(parsed["cron"]).to be_an(Array)
    end

    it "returns failure when the SSH client raises" do
      create(:scheduled_task, app_record: app)

      expect(client).to receive(:run).and_raise(Dokku::Client::CommandError.new("boom"))

      result = described_class.new(app, client: client).sync!
      expect(result.success?).to be false
      expect(result.error).to include("boom")
    end
  end
end
