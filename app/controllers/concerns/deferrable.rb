# frozen_string_literal: true

# Lets a controller serve "deferred sections" — the per-section endpoints
# behind the deferred_section helper's lazy turbo-frames. A controller
# declares its sections, defines a load_<section> method per section (the
# slow work), and provides a frames/_<section> partial that wraps its
# content in a matching turbo_frame_tag.
#
#   class FooController < ApplicationController
#     include Deferrable
#     deferred_sections :list, :activity
#     private
#     def load_list = (@things = ...)
#     def load_activity = (@events = ...)
#   end
#
# Route: get "sections/:section", to: "foo#section", as: :sections
module Deferrable
  extend ActiveSupport::Concern

  class_methods do
    def deferred_sections(*names)
      @deferred_section_names = names.map(&:to_sym)
    end

    def deferred_section_names
      @deferred_section_names || []
    end
  end

  # GET .../sections/:section — load the section's data, render its frame.
  #
  # `name` is resolved to one of the controller-declared section symbols
  # (a developer-defined allow-list), NOT reconstructed from params — the
  # request value is only used for equality matching. So the value handed
  # to `send` can only ever be `load_<one-of-the-declared-sections>`,
  # never arbitrary user input — which is also why Brakeman's Dangerous
  # Send check passes clean here (no ignore entry needed).
  def section
    name = self.class.deferred_section_names.find { |n| n.to_s == params[:section].to_s }
    return head(:not_found) unless name

    # Never cache a deferred section. These are per-user dynamic fragments;
    # a stale/empty cached copy surfaces as Turbo's "Content missing" after
    # a deploy or back-navigation.
    response.headers["Cache-Control"] = "no-store"

    send("load_#{name}")
    render partial: "#{controller_path}/frames/#{name}", layout: false
  end
end
