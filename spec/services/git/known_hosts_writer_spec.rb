# frozen_string_literal: true

require "rails_helper"

RSpec.describe Git::KnownHostsWriter do
  let(:server) { servers(:one) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:path) { File.join(tmpdir, "known_hosts") }

  after do
    FileUtils.remove_entry(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  def stub_scan(line)
    allow(described_class).to receive(:scan).and_return(line)
  end

  it "add writes a new known_hosts entry" do
    stub_scan("#{server.host} ssh-ed25519 AAAAEXAMPLE")
    line = described_class.add(server, path: path)
    expect(line).to eq("#{server.host} ssh-ed25519 AAAAEXAMPLE")
    expect(File.read(path)).to match(/ssh-ed25519 AAAAEXAMPLE/)
  end

  it "add is idempotent — running twice keeps a single entry" do
    stub_scan("#{server.host} ssh-ed25519 AAAATWICE")
    described_class.add(server, path: path)
    described_class.add(server, path: path)
    expect(File.read(path).scan(/ssh-ed25519/).size).to eq(1)
  end

  it "add rotates the line when the host key changes" do
    stub_scan("#{server.host} ssh-ed25519 AAAAOLD")
    described_class.add(server, path: path)
    stub_scan("#{server.host} ssh-ed25519 AAAANEW")
    described_class.add(server, path: path)

    body = File.read(path)
    expect(body).not_to match(/AAAAOLD/)
    expect(body).to match(/AAAANEW/)
  end

  it "add is a no-op when path is blank" do
    stub_scan("#{server.host} ssh-ed25519 AAAA")
    expect(described_class.add(server, path: nil)).to be_nil
  end

  it "remove deletes matching entries only" do
    File.write(path, <<~LINES)
      #{server.host} ssh-ed25519 AAAAKEEPME
      other-host ssh-ed25519 AAAAOTHER
    LINES
    described_class.remove(server, path: path)

    body = File.read(path)
    expect(body).not_to match(/AAAAKEEPME/)
    expect(body).to match(/AAAAOTHER/)
  end

  it "remove is safe to call when the file doesn't exist" do
    bogus = File.join(tmpdir, "does-not-exist")
    expect(described_class.remove(server, path: bogus)).to be_nil
  end

  it "non-standard port is written in [host]:port form and matched the same way" do
    server.update!(port: 2222)
    stub_scan("[#{server.host}]:2222 ssh-ed25519 AAAACUSTOMPORT")
    described_class.add(server, path: path)
    described_class.add(server, path: path)
    expect(File.read(path).scan(/ssh-ed25519/).size).to eq(1)
  end
end
