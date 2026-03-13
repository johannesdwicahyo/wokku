require "faraday"
require "json"

module Wokku
  class ApiClient
    class ApiError < StandardError
      attr_reader :status
      def initialize(message, status:)
        @status = status
        super(message)
      end
    end

    def initialize
      @url = ConfigStore.api_url
      @token = ConfigStore.token
      raise Error, "Not logged in. Run: wokku login" unless @url && @token

      @conn = Faraday.new(url: @url) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    def get(path, params = {})
      response = @conn.get("/api/v1/#{path}", params)
      handle_response(response)
    end

    def post(path, body = {})
      response = @conn.post("/api/v1/#{path}", body)
      handle_response(response)
    end

    def patch(path, body = {})
      response = @conn.patch("/api/v1/#{path}", body)
      handle_response(response)
    end

    def delete(path, body = {})
      response = @conn.delete("/api/v1/#{path}") { |req| req.body = body.to_json }
      handle_response(response)
    end

    private

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 401
        raise ApiError.new("Unauthorized. Run: wokku login", status: 401)
      when 404
        raise ApiError.new("Not found", status: 404)
      else
        error_msg = response.body.is_a?(Hash) ? response.body["error"] : response.body.to_s
        raise ApiError.new(error_msg || "Request failed (#{response.status})", status: response.status)
      end
    end
  end
end
