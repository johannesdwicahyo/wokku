# frozen_string_literal: true

module DeferredHelper
  # Declares a deferred page section: a lazy turbo-frame that shows a
  # skeleton immediately and is replaced by `src`'s response once it
  # loads. The shell view renders instantly; the heavy work lives behind
  # `src`. See docs/superpowers/specs/2026-06-08-instant-render-ux-design.md.
  def deferred_section(id, src:, skeleton: :card, **frame_opts)
    turbo_frame_tag(id, src: src, loading: "lazy", **frame_opts) do
      render(Molecules::SkeletonComponent.new(variant: skeleton))
    end
  end
end
