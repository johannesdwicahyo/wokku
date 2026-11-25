require "rails_helper"

RSpec.describe "layouts fonts" do
  %w[dashboard admin docs].each do |l|
    it "#{l} layout loads no Google text fonts (Geist is self-hosted)" do
      src = File.read(File.expand_path("../../app/views/layouts/#{l}.html.erb", __dir__))
      expect(src).not_to match(/Inter\+Tight|JetBrains\+Mono/)
    end
  end
end
