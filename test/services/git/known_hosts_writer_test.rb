require "test_helper"

class Git::KnownHostsWriterTest < ActiveSupport::TestCase
  setup do
    @server = servers(:one)
    @tmpdir = Dir.mktmpdir
    @path = File.join(@tmpdir, "known_hosts")
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def stub_scan(line)
    Git::KnownHostsWriter.stubs(:scan).returns(line)
  end

  test "add writes a new known_hosts entry" do
    stub_scan("#{@server.host} ssh-ed25519 AAAAEXAMPLE")
    line = Git::KnownHostsWriter.add(@server, path: @path)
    assert_equal "#{@server.host} ssh-ed25519 AAAAEXAMPLE", line
    assert_match(/ssh-ed25519 AAAAEXAMPLE/, File.read(@path))
  end

  test "add is idempotent — running twice keeps a single entry" do
    stub_scan("#{@server.host} ssh-ed25519 AAAATWICE")
    Git::KnownHostsWriter.add(@server, path: @path)
    Git::KnownHostsWriter.add(@server, path: @path)
    assert_equal 1, File.read(@path).scan(/ssh-ed25519/).size
  end

  test "add rotates the line when the host key changes" do
    stub_scan("#{@server.host} ssh-ed25519 AAAAOLD")
    Git::KnownHostsWriter.add(@server, path: @path)
    stub_scan("#{@server.host} ssh-ed25519 AAAANEW")
    Git::KnownHostsWriter.add(@server, path: @path)

    body = File.read(@path)
    refute_match(/AAAAOLD/, body)
    assert_match(/AAAANEW/, body)
  end

  test "add is a no-op when path is blank" do
    stub_scan("#{@server.host} ssh-ed25519 AAAA")
    assert_nil Git::KnownHostsWriter.add(@server, path: nil)
  end

  test "remove deletes matching entries only" do
    File.write(@path, <<~LINES)
      #{@server.host} ssh-ed25519 AAAAKEEPME
      other-host ssh-ed25519 AAAAOTHER
    LINES
    Git::KnownHostsWriter.remove(@server, path: @path)

    body = File.read(@path)
    refute_match(/AAAAKEEPME/, body)
    assert_match(/AAAAOTHER/, body)
  end

  test "remove is safe to call when the file doesn't exist" do
    bogus = File.join(@tmpdir, "does-not-exist")
    assert_nil Git::KnownHostsWriter.remove(@server, path: bogus)
  end

  test "non-standard port is written in [host]:port form and matched the same way" do
    @server.update!(port: 2222)
    stub_scan("[#{@server.host}]:2222 ssh-ed25519 AAAACUSTOMPORT")
    Git::KnownHostsWriter.add(@server, path: @path)
    Git::KnownHostsWriter.add(@server, path: @path)
    assert_equal 1, File.read(@path).scan(/ssh-ed25519/).size
  end
end
