module Organisms
  # Brutalist empty state used across list views (templates, notifications,
  # cloud credentials, activities, backups, log drains, etc.). Single
  # canonical pattern — no per-screen bespoke designs.
  class EmptyStateComponent < ApplicationComponent
    def initialize(headline:, body:, cta_label: nil, cta_href: nil, secondary_label: nil, secondary_href: nil)
      @headline = headline
      @body = body
      @cta_label = cta_label
      @cta_href = cta_href
      @secondary_label = secondary_label
      @secondary_href = secondary_href
    end
    attr_reader :headline, :body, :cta_label, :cta_href, :secondary_label, :secondary_href
  end
end
