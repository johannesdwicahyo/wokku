module Molecules
  class FlashToastComponent < ApplicationComponent
    def initialize(flash:)
      @flash = flash
    end

    def messages
      out = []
      out << { kind: "success", text: @flash[:notice] } if @flash[:notice].present?
      out << { kind: "error",   text: @flash[:alert] }  if @flash[:alert].present?
      out << { kind: "warn",    text: @flash[:warn] }   if @flash[:warn].present?
      out
    end
  end
end
