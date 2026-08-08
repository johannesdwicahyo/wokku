# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::SkeletonComponent, type: :component do
  Molecules::SkeletonComponent::VARIANTS.each do |variant|
    it "renders the #{variant} variant with a pulsing skeleton" do
      render_inline(described_class.new(variant: variant))

      expect(page).to have_css("[data-skeleton-variant='#{variant}']")
      expect(page).to have_css(".motion-safe\\:animate-pulse")
    end
  end

  it "falls back to :card for an unknown variant" do
    render_inline(described_class.new(variant: :nonsense))
    expect(page).to have_css("[data-skeleton-variant='card']")
  end

  it "honors the rows count for the table variant" do
    render_inline(described_class.new(variant: :table, rows: 5))
    expect(page).to have_css("[data-skeleton-row]", count: 5)
  end
end
