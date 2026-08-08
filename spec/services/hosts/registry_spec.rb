# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hosts::Registry do
  let(:client) { instance_double(Hosts::Ssh) }
  subject(:registry) { described_class.new(client) }

  describe "#push" do
    it "tags into the registry, pushes, and returns the registry ref" do
      expect(client).to receive(:run_raw)
        .with("docker tag wokku-rollback/blog:abc 127.0.0.1:5000/wokku-rollback/blog:abc && docker push 127.0.0.1:5000/wokku-rollback/blog:abc")
        .and_return("")
      expect(registry.push("wokku-rollback/blog:abc")).to eq("127.0.0.1:5000/wokku-rollback/blog:abc")
    end
  end

  describe "#tags" do
    it "lists tags via the registry HTTP API" do
      allow(client).to receive(:run_raw)
        .with("curl -sf http://127.0.0.1:5000/v2/wokku/blog/tags/list")
        .and_return('{"name":"wokku/blog","tags":["id-1","id-2"]}')
      expect(registry.tags("wokku/blog")).to eq(%w[id-1 id-2])
    end

    it "returns [] for an empty repo (registry answers tags:null) or garbage" do
      allow(client).to receive(:run_raw).and_return('{"name":"wokku/blog","tags":null}')
      expect(registry.tags("wokku/blog")).to eq([])
      allow(client).to receive(:run_raw).and_return("not json")
      expect(registry.tags("wokku/blog")).to eq([])
    end

    it "returns [] when run_raw raises CommandError (repo never pushed → 404)" do
      allow(client).to receive(:run_raw)
        .with("curl -sf http://127.0.0.1:5000/v2/wokku/blog/tags/list")
        .and_raise(Hosts::Ssh::CommandError, "curl: (22) The requested URL returned error: 404")
      expect(registry.tags("wokku/blog")).to eq([])
    end
  end

  describe "#delete_tag" do
    it "resolves the manifest digest then deletes it" do
      allow(client).to receive(:run_raw)
        .with(a_string_including("curl -sfI"))
        .and_return("HTTP/1.1 200 OK\r\nDocker-Content-Digest: sha256:deadbeef\r\n")
      expect(client).to receive(:run_raw)
        .with("curl -sf -X DELETE http://127.0.0.1:5000/v2/wokku/blog/manifests/sha256:deadbeef")
      registry.delete_tag("wokku/blog", "id-1")
    end

    it "is a no-op when no digest comes back" do
      allow(client).to receive(:run_raw).with(a_string_including("curl -sfI")).and_return("")
      expect(client).not_to receive(:run_raw).with(a_string_including("DELETE"))
      registry.delete_tag("wokku/blog", "id-1")
    end

    it "is a no-op when HEAD raises CommandError (tag already gone → 404)" do
      allow(client).to receive(:run_raw)
        .with(a_string_including("curl -sfI"))
        .and_raise(Hosts::Ssh::CommandError, "curl: (22) The requested URL returned error: 404")
      expect(client).not_to receive(:run_raw).with(a_string_including("DELETE"))
      expect(registry.delete_tag("wokku/blog", "id-1")).to be_nil
    end

    it "propagates a DELETE failure on an existing manifest" do
      allow(client).to receive(:run_raw)
        .with(a_string_including("curl -sfI"))
        .and_return("HTTP/1.1 200 OK\r\nDocker-Content-Digest: sha256:deadbeef\r\n")
      allow(client).to receive(:run_raw)
        .with(a_string_including("DELETE"))
        .and_raise(Hosts::Ssh::CommandError, "500 Internal Server Error")
      expect { registry.delete_tag("wokku/blog", "id-1") }.to raise_error(Hosts::Ssh::CommandError)
    end
  end
end
