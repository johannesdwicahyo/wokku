require "rails_helper"

RSpec.describe RejectMalformedUri do
  let(:downstream) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }
  subject(:middleware) { described_class.new(downstream) }

  it "passes a normal request through to the app" do
    status, _headers, body = middleware.call("PATH_INFO" => "/dashboard/apps/foo-bar_1", "QUERY_STRING" => "q=x")
    expect(status).to eq(200)
    expect(body).to eq([ "ok" ])
  end

  it "returns 400 for a path with invalid URI characters (scanner bot)" do
    status, headers, body = middleware.call("PATH_INFO" => "/shop/[category]/*", "QUERY_STRING" => "")
    expect(status).to eq(400)
    expect(headers["Content-Type"]).to match(%r{text/plain})
    expect(body.join).to match(/bad request/i)
  end

  it "does not call the downstream app for a malformed path" do
    called = false
    app = ->(_env) { called = true; [ 200, {}, [] ] }
    described_class.new(app).call("PATH_INFO" => "/x[y]", "QUERY_STRING" => "")
    expect(called).to be(false)
  end

  it "allows brackets in the QUERY STRING (legitimate Rails nested params)" do
    status, = middleware.call("PATH_INFO" => "/dashboard", "QUERY_STRING" => "user[name]=x")
    expect(status).to eq(200)
  end
end
