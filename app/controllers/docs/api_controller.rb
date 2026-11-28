module Docs
  # API reference: one Redoc page per group (Docs::ApiSlice), plus the
  # group's sliced OpenAPI document as JSON for Redoc to load.
  class ApiController < ApplicationController
    layout "docs"

    def index
      first = Docs::ApiSlice.groups.first or raise ActiveRecord::RecordNotFound
      redirect_to docs_api_group_path(first[:key], lang: params[:lang].presence)
    end

    def show
      @slice = Docs::ApiSlice.for(params[:group]) or raise ActiveRecord::RecordNotFound
      respond_to do |format|
        format.json do
          request.session_options[:skip] = true # publicly cached: never set a cookie
          expires_in 5.minutes, public: true
          render json: @slice.merge("servers" => [ { "url" => request.base_url } ]) # fresh hash: the cached slice stays shared
        end
        format.html do
          @docs_locale = resolve_locale
          I18n.locale = @docs_locale
          @docs_tab = :api
          @groups = Docs::ApiSlice.groups
          @group = @groups.find { |g| g[:key] == params[:group] }
        end
      end
    end

    private

    # Same order as DocsController: ?lang= → I18n.locale (?locale=, cookie…) → en.
    def resolve_locale
      candidate = params[:lang].presence || I18n.locale.to_s
      DocsController::SUPPORTED_LOCALES.include?(candidate) ? candidate : DocsController::DEFAULT_LOCALE
    end
  end
end
