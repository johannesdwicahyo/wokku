require "rails_helper"

RSpec.describe Atoms::LogoComponent, type: :component do
  it "draws seven lights with the middle one live" do
    html = render_inline(described_class.new(variant: :mark)).to_html
    expect(Nokogiri::HTML(html).css("svg rect").size).to eq 7
    expect(html).to include('fill="#22C55E"')
  end

  it "adds the wordmark in the lockup, by default" do
    page = render_inline(described_class.new)
    expect(page.css("svg path")).to be_present
    expect(page.css("svg[role=img][aria-label=Wokku][height='24']")).to be_present
  end

  it "keeps size: and href: working" do
    page = render_inline(described_class.new(size: :sm, href: "/"))
    expect(page.css("a[href='/'] svg[height='20']")).to be_present
    expect(render_inline(described_class.new(size: :lg)).css("svg[height='32']")).to be_present
  end

  it "draws the tile as a dark rounded square" do
    html = render_inline(described_class.new(variant: :tile)).to_html
    expect(html).to include('fill="#141414"')
  end
end
