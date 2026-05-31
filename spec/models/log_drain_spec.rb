require "rails_helper"

RSpec.describe LogDrain do
  def valid_drain
    LogDrain.new(
      app_record: app_records(:one),
      url: "syslog://logs.example.com:514",
      drain_type: "syslog"
    )
  end

  it "is valid with syslog url and syslog drain type" do
    expect(valid_drain).to be_valid
  end

  it "is valid with https url and https drain type" do
    drain = valid_drain
    drain.url = "https://logs.example.com/drain"
    drain.drain_type = "https"
    expect(drain).to be_valid
  end

  it "is valid with http url and https drain type" do
    drain = valid_drain
    drain.url = "http://logs.example.com/drain"
    drain.drain_type = "https"
    expect(drain).to be_valid
  end

  it "is invalid without url" do
    drain = valid_drain
    drain.url = nil
    expect(drain).to be_invalid
    expect(drain.errors[:url]).to include("can't be blank")
  end

  it "is invalid with malformed url" do
    drain = valid_drain
    drain.url = "not-a-url"
    expect(drain).to be_invalid
    expect(drain.errors[:url]).to include("must be a valid syslog or HTTP URL")
  end

  it "is invalid with ftp url" do
    drain = valid_drain
    drain.url = "ftp://logs.example.com"
    expect(drain).to be_invalid
    expect(drain.errors[:url]).to include("must be a valid syslog or HTTP URL")
  end

  it "is invalid with unknown drain type" do
    drain = valid_drain
    drain.drain_type = "kafka"
    expect(drain).to be_invalid
    expect(drain.errors[:drain_type]).to include("is not included in the list")
  end

  it "belongs to app_record" do
    drain = log_drains(:one)
    expect(drain.app_record).to eq(app_records(:one))
  end
end
