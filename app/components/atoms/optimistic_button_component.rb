module Atoms
  class OptimisticButtonComponent < ApplicationComponent
    def initialize(label:, url:, method: :post, pending_label: nil, kind: :primary, confirm: nil)
      @label, @url, @http_method = label, url, method
      @pending_label = pending_label || "#{label}…"
      @kind = kind
      @confirm = confirm
    end
    attr_reader :label, :url, :http_method, :pending_label, :kind, :confirm

    def classes
      base = "font-medium text-xs px-3 py-2 rounded-md transition-colors"
      base + (kind == :primary ? " bg-ink text-bg border border-ink hover:opacity-90" : " bg-paper text-ink border border-line hover:bg-bg")
    end
  end
end
