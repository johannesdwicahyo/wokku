# frozen_string_literal: true

require "rails_helper"

# Solid Queue refuses to start (and takes Puma down with it) when a recurring
# task names a class that doesn't exist — that silently broke self-host
# installs after RequestAggregateRollupJob was deleted (found 2026-11-16).
RSpec.describe "harness/config/recurring.yml" do
  it "only schedules job classes that exist" do
    config = YAML.load_file(Wokku::Engine.root.join("harness/config/recurring.yml"), aliases: true)
    classes = config.values.grep(Hash).flat_map(&:values).grep(Hash).filter_map { |task| task["class"] }.uniq
    expect(classes).not_to be_empty
    expect(classes.reject(&:safe_constantize)).to eq([])
  end
end
