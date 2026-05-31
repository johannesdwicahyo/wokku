# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Storage do
  let(:client) { double("client") }
  let(:storage) { described_class.new(client) }

  it "list returns mount specs from storage:list output" do
    output = <<~OUT
      =====> myapp storage information
      -----  -----------
      /var/lib/dokku/data/storage/myapp/data:/app/data
      /var/lib/dokku/data/storage/myapp/cache:/app/cache
    OUT
    expect(client).to receive(:run).with("storage:list myapp").and_return(output)
    expect(storage.list("myapp")).to eq([
      "/var/lib/dokku/data/storage/myapp/data:/app/data",
      "/var/lib/dokku/data/storage/myapp/cache:/app/cache"
    ])
  end

  it "list returns empty array when there are no mounts" do
    expect(client).to receive(:run).with("storage:list myapp").and_return("No mounts in app myapp")
    expect(storage.list("myapp")).to eq([])
  end

  it "ensure_directory shells out to storage:ensure-directory" do
    expect(client).to receive(:run).with("storage:ensure-directory myapp")
    storage.ensure_directory("myapp")
  end

  it "mount escapes the spec and shells out" do
    expect(client).to receive(:run).with("storage:mount myapp /host/path:/app/data")
    storage.mount("myapp", "/host/path:/app/data")
  end

  it "unmount shells out with the same spec" do
    expect(client).to receive(:run).with("storage:unmount myapp /host/path:/app/data")
    storage.unmount("myapp", "/host/path:/app/data")
  end

  it "list escapes app name with spaces" do
    expect(client).to receive(:run).with("storage:list weird\\ app")
    storage.list("weird app")
  end
end
