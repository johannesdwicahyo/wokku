module Api
  module V1
    class BaseController < ActionController::API
      include ApiAuthenticatable
      include Pundit::Authorization
      include Trackable
      # client_version_info — shared with MetaController (Task 3) so a
      # future /doctor endpoint (Task 4) can surface the same client:
      # {type, version, min_supported, outdated} shape without duplicating
      # the Gem::Version compare logic.
      include ClientVersion

      # Central error rendering (Track A Phase 3). Every rescue funnels
      # through ApiErrors so all three surfaces see one typed shape.
      rescue_from StandardError, with: :render_internal_error
      rescue_from ActiveRecord::RecordNotFound do |_e|
        render_api_error(:not_found)
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_api_error(:validation_failed,
                         message: e.record.errors.full_messages.to_sentence,
                         details: e.record.errors.full_messages)
      end
      rescue_from Pundit::NotAuthorizedError do |_e|
        render_api_error(:not_authorized)
      end
      # Hosts::Ssh command/connection failures → typed API errors.
      rescue_from Hosts::Ssh::CommandError, Hosts::Ssh::ConnectionError do |e|
        code = Hosts::ErrorClassifier.classify(e)
        # Keep the raw output visible for unclassified failures — it is
        # often the only clue (and what old clients displayed).
        message = code == :dokku_command_failed ? e.message : nil
        render_api_error(code, message: message)
      end

      private

      def render_api_error(code, message: nil, hint: nil, details: nil, status: nil)
        # A Live stream (logs follow) may already have committed the
        # response — rendering then raises a secondary error that buries
        # the original. The exception is still logged/Sentry-captured by
        # the caller; the stream itself was closed by its ensure block.
        return if response.committed?

        render json: ApiErrors.payload(code, message: message, hint: hint, details: details),
               status: status || ApiErrors.status(code)
      end

      def render_internal_error(exception)
        render_reported_error(:internal_error, exception)
      end

      # Report the real exception; answer with the typed generic message.
      def render_reported_error(code, exception)
        Sentry.capture_exception(exception) if defined?(Sentry)
        Rails.logger.error("[api] #{exception.class}: #{exception.message}")
        render_api_error(code)
      end
    end
  end
end
