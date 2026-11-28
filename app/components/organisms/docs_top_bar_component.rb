module Organisms
  # Docs top bar (guides + API reference): brand, section tabs, search,
  # EN/ID switch, Dashboard / Sign in. Changelog is a cloud route, so its
  # tab shows only when the host app defines `changelog_path`.
  class DocsTopBarComponent < ApplicationComponent
    def initialize(active:, locale:)
      @active = active.to_sym
      @locale = locale.to_sym
    end
    attr_reader :locale

    def tabs
      list = [
        [ :guides, t("docs.top.guides"), "/docs" ],
        [ :api, t("docs.top.api"), "/docs/api" ],
        [ :cli, t("docs.top.cli"), "/docs/cli" ]
      ]
      list << [ :changelog, t("docs.top.changelog"), helpers.changelog_path ] if helpers.respond_to?(:changelog_path)
      list
    end

    def current?(key) = key == @active
    def signed_in? = helpers.user_signed_in?
  end
end
