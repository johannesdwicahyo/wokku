# frozen_string_literal: true

module DeferredHelper
  # Declares a deferred page section: a lazy turbo-frame that shows a
  # skeleton immediately and is replaced by `src`'s response once it
  # loads. The shell view renders instantly; the heavy work lives behind
  # `src`. See docs/superpowers/specs/2026-06-08-instant-render-ux-design.md.
  # Seam (cloud) partials must not be able to 500 their host frame: log, report, skip.
  def render_seam_partial(section)
    render partial: section[:partial], locals: section[:locals] || {}
  rescue StandardError => e
    Rails.logger.error("seam partial #{section[:partial]} failed: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  def deferred_section(id, src:, skeleton: :card, **frame_opts)
    turbo_frame_tag(id, src: src, loading: "lazy", **frame_opts) do
      render(Molecules::SkeletonComponent.new(variant: skeleton))
    end
  end
end
