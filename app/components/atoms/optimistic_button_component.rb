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
      base = "border-1.5 border-ink font-mono text-[11px] uppercase tracking-widest px-3 py-2 shadow-brutal"
      base + (kind == :primary ? " bg-ink text-bg" : " bg-paper text-ink")
    end
  end
end
