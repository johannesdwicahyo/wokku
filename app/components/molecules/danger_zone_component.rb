module Molecules
  # schdl danger shell — the one shared container every destructive-action
  # surface (app delete, addon delete, account deletion) wraps its
  # confirm/type-to-confirm button(s) in. See U5 plan Locked decision #2.
  class DangerZoneComponent < ApplicationComponent
    def initialize(title:, body: nil)
      @title = title
      @body = body
    end
    attr_reader :title, :body
  end
end
