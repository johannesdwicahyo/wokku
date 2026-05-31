# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateRegistry do
  let(:registry) { described_class.new }

  it "loads templates from JSON files" do
    templates = registry.all
    expect(templates).to be_any
    expect(templates.first[:name]).to be_present
  end

  it "finds template by slug" do
    template = registry.find("rails-tailwind")
    expect(template[:name]).to eq("Rails + Tailwind")
    expect(template[:addons].first["type"]).to eq("postgres")
  end

  it "returns nil for unknown slug" do
    expect(registry.find("nonexistent")).to be_nil
  end

  it "filters by category" do
    frameworks = registry.by_category("frameworks")
    expect(frameworks.all? { |t| t[:category] == "frameworks" }).to be_truthy
  end

  it "searches by name and tags" do
    results = registry.search("rails")
    expect(results.any? { |t| t[:slug] == "rails-tailwind" }).to be_truthy
  end

  it "returns categories" do
    cats = registry.categories
    expect(cats.any? { |c| c["slug"] == "frameworks" }).to be_truthy
  end
end
