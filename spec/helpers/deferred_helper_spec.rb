# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeferredHelper, type: :helper do
  it "renders a lazy turbo-frame with the src and an enclosed skeleton" do
    html = helper.deferred_section("apps_list", src: "/dashboard/apps/sections?section=list", skeleton: :table)

    expect(html).to include("<turbo-frame")
    expect(html).to include('id="apps_list"')
    expect(html).to include('src="/dashboard/apps/sections?section=list"')
    expect(html).to include('loading="lazy"')
    expect(html).to include("data-skeleton-variant=\"table\"")
  end

  it "defaults to the :card skeleton" do
    html = helper.deferred_section("x", src: "/y")
    expect(html).to include("data-skeleton-variant=\"card\"")
  end
end
