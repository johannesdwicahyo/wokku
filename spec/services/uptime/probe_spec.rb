# frozen_string_literal: true

require "rails_helper"
require "ssrf_filter"

# Probe routes through SsrfFilter (resolves + validates a public IP, pins
# the socket, follows/revalidates redirects), so these unit specs stub at
# the SsrfFilter seam rather than Net::HTTP — SsrfFilter connects to the
# resolved IP, which WebMock's hostname stubs never match.
RSpec.describe Uptime::Probe do
  def resp(code) = instance_double(Net::HTTPResponse, code: code.to_s)

  it "is up on 200" do
    allow(SsrfFilter).to receive(:get).and_return(resp(200))
    expect(described_class.call("https://app.example.com/")).to be_up
  end

  it "is up on 404 — a responding app is alive" do
    allow(SsrfFilter).to receive(:get).and_return(resp(404))
    expect(described_class.call("https://app.example.com/")).to be_up
  end

  it "strikes with :http_5xx on 503" do
    allow(SsrfFilter).to receive(:get).and_return(resp(503))
    result = described_class.call("https://app.example.com/")
    expect(result).not_to be_up
    expect(result.failure_kind).to eq(:http_5xx)
  end

  it "blocks SSRF to non-public addresses with :blocked" do
    allow(SsrfFilter).to receive(:get).and_raise(SsrfFilter::Error)
    result = described_class.call("http://127.0.0.1:5000/")
    expect(result).not_to be_up
    expect(result.failure_kind).to eq(:blocked)
  end

  it "strikes with :timeout on Net::OpenTimeout" do
    allow(SsrfFilter).to receive(:get).and_raise(Net::OpenTimeout)
    expect(described_class.call("https://app.example.com/").failure_kind).to eq(:timeout)
  end

  it "strikes with :connection_refused on ECONNREFUSED" do
    allow(SsrfFilter).to receive(:get).and_raise(Errno::ECONNREFUSED)
    expect(described_class.call("https://app.example.com/").failure_kind).to eq(:connection_refused)
  end

  it "strikes with :dns_error on SocketError" do
    allow(SsrfFilter).to receive(:get).and_raise(SocketError)
    expect(described_class.call("https://app.example.com/").failure_kind).to eq(:dns_error)
  end

  it "falls back to plain http ONCE on SSL error, and is up if http answers" do
    allow(SsrfFilter).to receive(:get).with("https://app.example.com/", anything).and_raise(OpenSSL::SSL::SSLError)
    allow(SsrfFilter).to receive(:get).with("http://app.example.com/", anything).and_return(resp(200))
    expect(described_class.call("https://app.example.com/")).to be_up
  end

  it "strikes with :ssl_error when the http fallback also fails" do
    allow(SsrfFilter).to receive(:get).and_raise(OpenSSL::SSL::SSLError)
    expect(described_class.call("https://app.example.com/").failure_kind).to eq(:ssl_error)
  end

  it "delegates redirect-following to SsrfFilter with a bounded hop budget" do
    allow(SsrfFilter).to receive(:get).and_return(resp(200))
    expect(described_class.call("https://app.example.com/")).to be_up
    expect(SsrfFilter).to have_received(:get).with("https://app.example.com/", hash_including(max_redirects: 3))
  end
end
