require "test_helper"

class Dokku::StorageTest < ActiveSupport::TestCase
  setup do
    @client = mock("client")
    @storage = Dokku::Storage.new(@client)
  end

  test "list returns mount specs from storage:list output" do
    output = <<~OUT
      =====> myapp storage information
      -----  -----------
      /var/lib/dokku/data/storage/myapp/data:/app/data
      /var/lib/dokku/data/storage/myapp/cache:/app/cache
    OUT
    @client.expects(:run).with("storage:list myapp").returns(output)
    assert_equal [
      "/var/lib/dokku/data/storage/myapp/data:/app/data",
      "/var/lib/dokku/data/storage/myapp/cache:/app/cache"
    ], @storage.list("myapp")
  end

  test "list returns empty array when there are no mounts" do
    @client.expects(:run).with("storage:list myapp").returns("No mounts in app myapp")
    assert_equal [], @storage.list("myapp")
  end

  test "ensure_directory shells out to storage:ensure-directory" do
    @client.expects(:run).with("storage:ensure-directory myapp")
    @storage.ensure_directory("myapp")
  end

  test "mount escapes the spec and shells out" do
    @client.expects(:run).with("storage:mount myapp /host/path:/app/data")
    @storage.mount("myapp", "/host/path:/app/data")
  end

  test "unmount shells out with the same spec" do
    @client.expects(:run).with("storage:unmount myapp /host/path:/app/data")
    @storage.unmount("myapp", "/host/path:/app/data")
  end

  test "list escapes app name with spaces" do
    @client.expects(:run).with("storage:list weird\\ app")
    @storage.list("weird app")
  end
end
