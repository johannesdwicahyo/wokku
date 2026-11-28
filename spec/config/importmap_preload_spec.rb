require "rails_helper"

RSpec.describe "importmap" do
  it "does not modulepreload the terminal-only xterm pins" do
    pins = Rails.application.importmap.preloaded_module_paths(resolver: ActionController::Base.helpers).join(" ")
    expect(pins).not_to include("xterm")
    expect(pins).to include("application")
  end
end
