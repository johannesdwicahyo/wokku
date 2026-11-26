# frozen_string_literal: true

module Organisms
  # One attached add-on on the create form. Always posts the same six hidden
  # inputs (addons[][kind] first) so Rack groups consecutive rows correctly;
  # new_app_controller clones a blank one from a <template> and fills it.
  class NewAppAddonRowComponent < ApplicationComponent
    FIELDS = %w[kind engine cpu memory_mb disk_gb database_service_id].freeze

    def initialize(item: {}, label: "", env: "", price_text: "", price: 0)
      @item, @label, @env, @price_text, @price = item.to_h.stringify_keys, label, env, price_text, price
    end
    attr_reader :label, :env, :price_text, :price

    def value(field) = @item[field]
  end
end
