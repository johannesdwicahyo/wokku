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
      base = "inline-flex items-center justify-center font-semibold text-xs px-3 py-2 rounded-md transition-[transform,box-shadow,background-color] duration-75 active:translate-x-[2px] active:translate-y-[2px] active:shadow-none"
      base + (kind == :primary ? " bg-ink text-paper border-1.5 border-ink shadow-brutal hover:bg-ink/90" : " bg-paper text-ink border-1.5 border-ink shadow-brutal-sm hover:bg-bg-deep")
    end
  end
end
