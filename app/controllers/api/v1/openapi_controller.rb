module Api
  module V1
    # Public, unauthenticated: the contract is documentation, nothing secret.
    class OpenapiController < ActionController::API
      def show
        send_file Wokku.config.openapi_path, type: "application/yaml; charset=utf-8", disposition: "inline"
      end
    end
  end
end
