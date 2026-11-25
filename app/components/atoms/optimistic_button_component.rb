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
      base = "inline-flex items-center justify-center font-semibold text-xs px-3 py-2 rounded-md transition-[transform,box-shadow,background-color] duration-75"
      base + (kind == :primary ? " bg-live text-[#03140A] border border-live hover:bg-live-hover" : " bg-transparent text-ink border border-line-strong hover:border-ink")
    end
  end
end
